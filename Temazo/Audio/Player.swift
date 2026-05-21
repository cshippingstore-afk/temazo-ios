import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer

/// Player híbrido — usa dos motores según foreground/background:
///   - **Foreground**: IframePlayerEngine (iframe oficial youtube-nocookie)
///                    → views cuentan, royalties al artista, 100% legal frente YT ToS.
///   - **Background**: AvPlayerEngine (AVPlayer con stream extraído via yt_proxy.php)
///                    → necesario porque WKWebView no funciona en background en iOS.
///
/// Switch automático en `UIApplication.didEnterBackgroundNotification` /
/// `willEnterForegroundNotification`. La posición se sincroniza entre engines
/// para que el cambio sea inaudible.
///
/// La API pública (playTrack, togglePlay, next, prev, seekTo) no cambia — la UI
/// funciona igual.
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private let iframe = IframePlayerEngine.shared
    private let avplayer = AvPlayerEngine.shared

    /// Engine activo: empieza en .iframe (foreground) y conmuta según lifecycle.
    enum ActiveEngine { case iframe, avplayer }
    private(set) var active: ActiveEngine = .iframe

    private var crossfadeMs: Int = 250
    private var hookedEngine = false
    private var bgObserver: NSObjectProtocol?
    private var fgObserver: NSObjectProtocol?

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        hookEngineCallbacks()
        observeAppLifecycle()
    }

    deinit {
        if let o = bgObserver { NotificationCenter.default.removeObserver(o) }
        if let o = fgObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - API pública (no cambia)

    func playTrack(_ track: Track, queue: [Track], index: Int) {
        state.queue = queue
        state.index = index
        state.currentTrack = track
        state.positionSec = 0
        state.durationSec = Float(track.durationSec ?? 0)
        state.lastError = nil
        state.loadingState = .extracting
        AudioSessionManager.shared.ensureActive()
        AudioSessionManager.shared.startSilentLoop()
        startCurrentEngine(forTrack: track, fromSeconds: 0, autoplay: true)
    }

    func togglePlay() { if state.isPlaying { pause() } else { resume() } }

    func resume() {
        AudioSessionManager.shared.ensureActive()
        AudioSessionManager.shared.startSilentLoop()
        switch active {
        case .iframe:   iframe.play()
        case .avplayer: avplayer.play()
        }
        state.isPlaying = true
    }

    func pause() {
        switch active {
        case .iframe:   iframe.pause()
        case .avplayer: avplayer.pause()
        }
        state.isPlaying = false
        AudioSessionManager.shared.stopSilentLoop()
    }

    /// Añade un track al final de la cola actual sin interrumpir reproducción.
    func addToQueue(_ track: Track) {
        if state.queue.contains(where: { $0.id == track.id }) { return }
        state.queue.append(track)
    }

    func next() {
        guard !state.queue.isEmpty else { return }
        let nextIdx = (state.index + 1) % state.queue.count
        let t = state.queue[nextIdx]
        state.index = nextIdx
        state.currentTrack = t
        state.positionSec = 0
        state.durationSec = Float(t.durationSec ?? 0)
        state.loadingState = .extracting
        startCurrentEngine(forTrack: t, fromSeconds: 0, autoplay: true)
    }

    func prev() {
        guard !state.queue.isEmpty else { return }
        let prevIdx = state.index <= 0 ? state.queue.count - 1 : state.index - 1
        let t = state.queue[prevIdx]
        state.index = prevIdx
        state.currentTrack = t
        state.positionSec = 0
        state.durationSec = Float(t.durationSec ?? 0)
        state.loadingState = .extracting
        startCurrentEngine(forTrack: t, fromSeconds: 0, autoplay: true)
    }

    func seekTo(seconds: Float) {
        state.positionSec = seconds
        switch active {
        case .iframe:   iframe.seek(seconds: Double(seconds))
        case .avplayer: avplayer.seek(seconds: Double(seconds))
        }
    }

    func stopAll() {
        iframe.pause()
        avplayer.stop()
        AudioSessionManager.shared.stopSilentLoop()
        state = PlayerState()
    }

    func setCrossfadeMs(_ ms: Int) { crossfadeMs = max(150, min(6000, ms)) }

    // MARK: - Internal: arrancar engine activo

    private func startCurrentEngine(forTrack track: Track, fromSeconds: Double, autoplay: Bool) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"; state.loadingState = .failed; return
        }
        // CRÍTICO: calentar yt_proxy.php SIEMPRE que cambia el track. Sin esto, el primer
        // bloqueo de pantalla tras play tarda 30-60s porque yt-dlp tiene que extraer.
        // El endpoint yt_resolve.php solo cachea la URL del stream (no proxya bytes) → rápido.
        TemazoAPI.shared.prefetchYouTubeURLs([ytId])

        switch active {
        case .iframe:
            iframe.load(youtubeId: ytId)
            if fromSeconds > 0.5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.iframe.seek(seconds: fromSeconds)
                }
            }
            // Pre-armado del AVPlayer (sin play). Cuando la app va a BG, el item
            // ya está armado → seek+play instantáneo.
            avplayer.preload(ytId: ytId)
        case .avplayer:
            avplayer.load(ytId: ytId, fromSeconds: fromSeconds, autoplay: autoplay)
        }
    }

    // MARK: - Lifecycle: switch entre engines

    private func observeAppLifecycle() {
        bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.switchToBackgroundEngine() }
        }
        fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.switchToForegroundEngine() }
        }
    }

    /// Foreground → Background: pausar iframe, arrancar AVPlayer en la posición actual.
    /// El AVPlayer YA está pre-cargado (preload en playTrack), así que aquí solo seek + play.
    private func switchToBackgroundEngine() {
        guard active == .iframe else { return }
        guard let track = state.currentTrack, state.isPlaying else {
            return
        }
        let pos = Double(state.positionSec)
        print("[Player] FG→BG switch at \(pos)s — iframe→avplayer (preloaded)")
        iframe.pause()
        active = .avplayer
        AudioSessionManager.shared.ensureActive()
        AudioSessionManager.shared.startSilentLoop()
        guard let ytId = track.youtubeId, !ytId.isEmpty else { return }
        // Si el preload coincide con el track actual, solo seek+play (instantáneo).
        // Si no (track cambió entre preload y switch), hacer load completo como fallback.
        if avplayer.currentYtId == ytId {
            avplayer.seek(seconds: pos)
            avplayer.play()
        } else {
            avplayer.load(ytId: ytId, fromSeconds: pos, autoplay: true)
        }
    }

    /// Background → Foreground: pausar AVPlayer, retomar iframe en la posición actual.
    private func switchToForegroundEngine() {
        guard active == .avplayer else { return }
        let pos = avplayer.currentPosition
        print("[Player] BG→FG switch at \(pos)s — avplayer→iframe")
        // Actualizar state.positionSec con la posición real del avplayer
        state.positionSec = Float(pos)
        avplayer.pause()
        active = .iframe
        // El iframe puede haberse "dormido" en background, recargamos el track en
        // su posición actual para asegurar continuidad.
        guard let track = state.currentTrack,
              let ytId = track.youtubeId, !ytId.isEmpty else { return }
        iframe.load(youtubeId: ytId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.iframe.seek(seconds: pos)
        }
    }

    // MARK: - Engine callbacks

    private func hookEngineCallbacks() {
        guard !hookedEngine else { return }
        hookedEngine = true

        // Iframe events
        iframe.onReady = { print("[Player] iframe ready") }

        iframe.onStateChange = { [weak self] s in
            Task { @MainActor [weak self] in
                guard let self = self, self.active == .iframe else { return }
                switch s {
                case .playing:
                    self.state.isPlaying = true
                    self.state.ready = true
                    self.state.loadingState = .playing
                case .paused:
                    self.state.isPlaying = false
                    self.state.loadingState = .ready
                case .buffering:
                    self.state.loadingState = .stalled
                case .ended:
                    self.next()
                case .cued:
                    self.state.loadingState = .ready
                case .unstarted, .unknown:
                    break
                }
            }
        }

        iframe.onTime = { [weak self] pos, dur in
            Task { @MainActor [weak self] in
                guard let self = self, self.active == .iframe else { return }
                self.state.positionSec = Float(pos)
                if self.state.durationSec == 0, dur > 0 {
                    self.state.durationSec = Float(dur)
                }
            }
        }

        iframe.onError = { [weak self] code in
            Task { @MainActor [weak self] in
                guard let self = self, self.active == .iframe else { return }
                self.state.lastError = "YT error \(code)"
                self.state.loadingState = .failed
                if code == 100 || code == 101 || code == 150 { self.next() }
            }
        }

        // AVPlayer events
        avplayer.onTime = { [weak self] pos in
            Task { @MainActor [weak self] in
                guard let self = self, self.active == .avplayer else { return }
                self.state.positionSec = Float(pos)
            }
        }

        avplayer.onEnded = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.active == .avplayer else { return }
                self.next()
            }
        }

        avplayer.onError = { [weak self] msg in
            Task { @MainActor [weak self] in
                guard let self = self, self.active == .avplayer else { return }
                self.state.lastError = msg
                self.state.loadingState = .failed
            }
        }
    }
}
