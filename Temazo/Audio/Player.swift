import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer

/// Player iOS basado en WKWebView + YouTube IFrame Player API (v2.21).
///
/// Misma arquitectura que el Android Player.kt (que reproduce sin lag):
///  - WebPlayerEngine pre-carga la página HTML al arrancar la app
///  - Las canciones se cargan con `player.loadVideoById()` JS — 50-100ms
///  - El WebView vive en una UIView 1×1 px de MainScreen (no se destruye)
///  - AVAudioSession + silent loop mantienen audio en background
///  - MediaSession via MPNowPlayingInfoCenter (lock screen + auriculares + coche)
///
/// API pública IDÉNTICA a la versión AVPlayer → el resto de la app (MiniPlayer,
/// FullPlayer, MainScreen, NowPlayingManager, etc.) no necesita cambios.
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private let engine = WebPlayerEngine.shared
    /// Flag para evitar doble next() entre estado "ended" del player y nuestro
    /// detector manual via positionSec ≥ durationSec - 0.4s.
    private var didAutoNext: Bool = false
    private var crossfadeMs: Int = 250

    /// v2.39: Hybrid background switcher.
    /// WKWebView no sobrevive al lock screen porque iOS suspende el proceso
    /// WebKit (PID distinto). Cuando la app entra background CON música
    /// reproduciendo, traspasamos el audio al AVPlayer streaming via
    /// temazo.es/api/yt_proxy.php — AVPlayer SÍ aguanta lock porque es la
    /// arquitectura nativa iOS para background audio (UIBackgroundModes audio).
    /// Al volver a foreground, traspasamos de vuelta al iframe.
    private var bgAVPlayer: AVPlayer?
    private var bgTimeObs: Any?
    private var bgEndObs: NSObjectProtocol?
    /// true mientras estamos reproduciendo via bgAVPlayer (background mode)
    private var inBackgroundPlayback: Bool = false

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        AudioSessionManager.shared.ensureActive()
        wireEngine()
        // v2.39: observers del lifecycle para hybrid switcher
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    // MARK: - v2.39 Hybrid Background Switcher

    @objc private func handleEnteredBackground() {
        // Solo activamos el switch si HAY música sonando
        guard state.isPlaying, let track = state.currentTrack,
              let ytId = track.youtubeId, !ytId.isEmpty else {
            print("[Player] background: nada que reproducir, skip switch")
            return
        }
        let currentPos = state.positionSec
        print("[Player] background → switching iframe → AVPlayer en pos=\(currentPos)")
        // Pausa el iframe (WebKit se va a suspender de todos modos al bloquear)
        engine.pause()
        // Arranca AVPlayer con el proxy
        let urlStr = "https://temazo.es/api/yt_proxy.php?id=\(ytId)"
        guard let url = URL(string: urlStr) else { return }
        let item = AVPlayerItem(url: url)
        let avp = AVPlayer(playerItem: item)
        avp.automaticallyWaitsToMinimizeStalling = false
        // Seek al punto donde estábamos en el iframe
        if currentPos > 1 {
            let cm = CMTime(seconds: Double(currentPos), preferredTimescale: 600)
            avp.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                avp.play()
            }
        } else {
            avp.play()
        }
        // Position updates desde AVPlayer durante background
        bgTimeObs = avp.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] t in
            guard let self else { return }
            self.state.positionSec = Float(t.seconds)
        }
        // Auto-next al terminar
        bgEndObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
        bgAVPlayer = avp
        inBackgroundPlayback = true
    }

    @objc private func handleWillEnterForeground() {
        guard inBackgroundPlayback, let avp = bgAVPlayer else { return }
        let pos = Float(avp.currentTime().seconds)
        print("[Player] foreground → switching AVPlayer → iframe en pos=\(pos)")
        // Cleanup AVPlayer
        if let obs = bgTimeObs { avp.removeTimeObserver(obs); bgTimeObs = nil }
        if let obs = bgEndObs { NotificationCenter.default.removeObserver(obs); bgEndObs = nil }
        avp.pause()
        avp.replaceCurrentItem(with: nil)
        bgAVPlayer = nil
        inBackgroundPlayback = false
        // Re-seek + resume iframe en la posición exacta
        if pos > 1 { engine.seek(toSec: pos) }
        engine.resume()
        state.positionSec = pos
    }

    private func wireEngine() {
        engine.onReady = { [weak self] in
            print("[Player] engine ready")
            self?.state.loadingState = .ready
            self?.state.ready = true
        }

        engine.onStateChange = { [weak self] name, code in
            guard let self else { return }
            switch name {
            case "playing":
                self.state.isPlaying = true
                self.state.loadingState = .playing
                self.didAutoNext = false
                AudioSessionManager.shared.ensureActive()
                // v2.35: silent loop reactivado. Con .mixWithOthers (configure()),
                // el AVAudioPlayer silencioso a 0.05 NO le roba el output al iframe
                // — coexisten. Sin él, iOS suspende el WKWebView al bloquear pantalla
                // porque considera que el proceso no produce audio "real".
                AudioSessionManager.shared.startSilentLoop()
            case "paused":
                // v2.29: el watchdog JS dentro del iframe (cycle 250ms) detecta
                // y revierte las pausas falsas de iOS sin round-trip a Swift.
                // Aquí solo reflejamos el state. Si fue pausa real (user pulsó
                // pause), el watchdog NO interferirá porque tmzPause() ya puso
                // shouldBePlaying=false antes de llamar pauseVideo().
                if !self.state.isPlaying {
                    // pausa real del user
                } else {
                    // pausa de iOS — el watchdog JS la revertirá; NO cambiamos
                    // state.isPlaying para que la UI no parpadee.
                    print("[Player] iframe paused (probable iOS auto-pause) — watchdog JS recuperará")
                }
            case "buffering":
                self.state.loadingState = .extracting
            case "ended":
                if !self.didAutoNext {
                    self.didAutoNext = true
                    self.next()
                }
            case "cued":
                break
            case "unstarted":
                break
            default: break
            }
        }

        engine.onError = { [weak self] code in
            self?.state.lastError = "yt error \(code)"
            self?.state.loadingState = .failed
            // YouTube error 150 / 101 = video bloqueado en este país. Skip al siguiente.
            if code == 150 || code == 101 {
                self?.next()
            }
        }

        engine.onTime = { [weak self] pos, dur in
            guard let self else { return }
            self.state.positionSec = pos
            if dur > 0 { self.state.durationSec = dur }
            // Auto-next manual de seguridad (si el evento 'ended' no llega)
            if self.state.durationSec > 1,
               pos >= self.state.durationSec - 0.4,
               self.state.isPlaying,
               !self.didAutoNext {
                self.didAutoNext = true
                self.next()
            }
        }
    }

    // MARK: - API pública

    func playTrack(_ track: Track, queue: [Track], index: Int, source: String? = nil) {
        state.queue = queue
        state.index = index
        state.currentTrack = track
        state.positionSec = 0
        state.source = source
        // Duración del backend = source of truth; el iframe la corregirá si difiere.
        state.durationSec = Float(track.durationSec ?? 0)
        state.lastError = nil
        state.loadingState = .extracting
        didAutoNext = false
        AudioSessionManager.shared.ensureActive()
        startCurrentTrack()
        Task { try? await TemazoAPI.shared.historyAdd(track.id) }
    }

    /// v2.39: arranca el track actual en el engine ACTIVO (iframe o AVPlayer
    /// según estemos en foreground o background).
    private func startCurrentTrack() {
        guard let track = state.currentTrack,
              let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"
            state.loadingState = .failed
            return
        }
        if inBackgroundPlayback {
            // En background: swap del AVPlayerItem
            let urlStr = "https://temazo.es/api/yt_proxy.php?id=\(ytId)"
            guard let url = URL(string: urlStr), let avp = bgAVPlayer else { return }
            // Cleanup observer del item anterior
            if let obs = bgEndObs { NotificationCenter.default.removeObserver(obs); bgEndObs = nil }
            let item = AVPlayerItem(url: url)
            avp.replaceCurrentItem(with: item)
            avp.play()
            bgEndObs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.next() }
            }
        } else {
            engine.play(videoId: ytId)
        }
        state.isPlaying = true
    }

    /// Cicla repeat: OFF → REPEAT_ALL → REPEAT_ONE → OFF
    func toggleRepeat() {
        state.repeatMode = (state.repeatMode + 1) % 3
    }

    /// Toggle shuffle. Reordena la cola en sitio (sin parar la reproducción actual).
    func toggleShuffle() {
        state.shuffle.toggle()
        guard !state.queue.isEmpty, let current = state.currentTrack else { return }
        if state.shuffle {
            var rest = state.queue
            rest.remove(at: state.index)
            rest.shuffle()
            state.queue = [current] + rest
            state.index = 0
        }
    }

    func togglePlay() { if state.isPlaying { pause() } else { resume() } }

    func resume() {
        AudioSessionManager.shared.ensureActive()
        state.isPlaying = true
        if inBackgroundPlayback {
            bgAVPlayer?.play()
        } else {
            engine.resume()
        }
    }

    func pause() {
        print("[Player] pause() called")
        state.isPlaying = false
        if inBackgroundPlayback {
            bgAVPlayer?.pause()
        } else {
            engine.pause()
            AudioSessionManager.shared.stopSilentLoop()
        }
    }

    /// Añade un track al final de la cola actual sin interrumpir reproducción.
    func addToQueue(_ track: Track) {
        if state.queue.contains(where: { $0.id == track.id }) { return }
        state.queue.append(track)
    }

    func next() {
        guard !state.queue.isEmpty else { return }

        // REPEAT_ONE: recargar la misma canción
        if state.repeatMode == 2, state.index >= 0, state.index < state.queue.count {
            let t = state.queue[state.index]
            state.currentTrack = t
            state.positionSec = 0
            state.durationSec = Float(t.durationSec ?? 0)
            state.loadingState = .extracting
            didAutoNext = false
            startCurrentTrack()
            Task { try? await TemazoAPI.shared.historyAdd(t.id) }
            return
        }

        let atEnd = (state.index + 1) >= state.queue.count
        // OFF: al final de la cola, parar (no wrap)
        if state.repeatMode == 0, atEnd {
            pause()
            state.positionSec = 0
            return
        }

        let nextIdx = (state.index + 1) % state.queue.count
        let t = state.queue[nextIdx]
        state.index = nextIdx
        state.currentTrack = t
        state.positionSec = 0
        state.durationSec = Float(t.durationSec ?? 0)
        state.loadingState = .extracting
        didAutoNext = false
        startCurrentTrack()
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
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
        didAutoNext = false
        startCurrentTrack()
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func seekTo(seconds: Float) {
        if inBackgroundPlayback, let avp = bgAVPlayer {
            let cm = CMTime(seconds: Double(seconds), preferredTimescale: 600)
            avp.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            engine.seek(toSec: seconds)
        }
        state.positionSec = seconds
    }

    func stopAll() {
        engine.stop()
        AudioSessionManager.shared.stopSilentLoop()
        state = PlayerState()
    }

    func setCrossfadeMs(_ ms: Int) { crossfadeMs = max(150, min(6000, ms)) }
}
