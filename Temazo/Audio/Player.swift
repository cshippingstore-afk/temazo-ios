import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer

/// Player iOS v2.43 — DUAL ENGINE PARALELO (iframe + AVPlayer simultáneos)
///
/// Arquitectura final tras 8h de iteraciones fallidas con switchers:
///  - iframe (WKWebView): único motor AUDIBLE en foreground. Da el arranque
///    instantáneo y la UX que el user pidió ("como Android").
///  - parallelAVPlayer: AVPlayer corriendo en paralelo desde el primer play,
///    con la misma canción extraída por YouTubeExtractor, AL VOLUMEN 0 en
///    foreground. iOS lo registra como audio "real" del proceso → mantiene
///    la app + WebKit vivos en background + sobrevive al lock.
///  - Sincronización continua: cada tick de iframe.onTime comprueba drift del
///    AVPlayer paralelo y le hace seek si se desvía >1s.
///  - Lock screen: parallelAVPlayer.volume = 1 + iframe.pause(). Sin gap, sin
///    extract cold, sin replaceCurrentItem.
///  - Unlock: iframe.seek + iframe.resume + parallelAVPlayer.volume = 0.
///
/// Por qué los switchers (v2.39-v2.42) fallaban:
///   El AVPlayer arrancaba EN el momento del lock → seek/extract latency = gap
///   audible. Y replaceCurrentItem entre tracks dejaba la session desactivada
///   = mute. Solución: el AVPlayer YA está corriendo cuando llega el lock,
///   solo hay que subirle volumen.
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private let engine = WebPlayerEngine.shared
    private var didAutoNext: Bool = false
    private var crossfadeMs: Int = 250

    /// v2.43: AVPlayer paralelo que SIEMPRE corre cuando hay música.
    /// Volumen 0 en foreground (iframe audible), volumen 1 al bloquear.
    private var parallelPlayer: AVPlayer?
    private var parallelItem: AVPlayerItem?
    private var parallelEndObs: NSObjectProtocol?
    private var parallelTimeObs: Any?
    /// ID del track cargado en el paralelo (para evitar re-cargas redundantes).
    private var parallelLoadedYtId: String?
    /// true = app en background, parallel está audible.
    private var inBackground: Bool = false

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        AudioSessionManager.shared.ensureActive()
        wireEngine()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    // MARK: - v2.43 Lifecycle bg/fg

    @objc private func handleEnteredBackground() {
        guard state.isPlaying else { return }
        print("[Player] → BG: iframe pause, parallel volume = 1")
        inBackground = true
        // 1. Pausar iframe (WebKit se suspendería de todas formas, mejor explícito)
        engine.pause()
        // 2. Subir volumen del paralelo. Como YA está corriendo en sync, no hay gap.
        if let avp = parallelPlayer {
            // Asegurar session activa (iOS la puede haber tocado)
            try? AVAudioSession.sharedInstance().setActive(true, options: [])
            avp.volume = 1.0
            // Por si estaba pausado por sync inicial
            if avp.rate == 0 && state.isPlaying { avp.play() }
        } else {
            print("[Player] BG: parallel no ready → cold start fallback")
            // Fallback: parallel no estaba listo (track recién tappeado).
            // Arrancarlo ahora con extractor.
            coldStartParallel()
        }
    }

    @objc private func handleWillEnterForeground() {
        print("[Player] → FG: iframe resume, parallel volume = 0")
        inBackground = false
        // Bajar volumen del paralelo PRIMERO para evitar echo durante la transición
        let parallelPos = Float(parallelPlayer?.currentTime().seconds ?? 0)
        parallelPlayer?.volume = 0
        // Resumir iframe en la posición del paralelo (que es la "real")
        if state.isPlaying {
            if parallelPos > 1 { engine.seek(toSec: parallelPos) }
            engine.resume()
            state.positionSec = parallelPos
        }
    }

    /// v2.43: arranca el paralelo cuando aún no había URL al bloquear.
    /// Edge case raro pero posible si user toca play + bloquea en <500ms.
    private func coldStartParallel() {
        guard let track = state.currentTrack,
              let ytId = track.youtubeId, !ytId.isEmpty else { return }
        let pos = state.positionSec
        Task { @MainActor in
            do {
                let url = try await YouTubeExtractor.shared.extractStreamURL(videoID: ytId, timeoutSec: 5)
                self.spawnParallel(url: url, ytId: ytId, startAt: pos, audible: true)
            } catch {
                if let purl = URL(string: "https://temazo.es/api/yt_proxy.php?id=\(ytId)") {
                    self.spawnParallel(url: purl, ytId: ytId, startAt: pos, audible: true)
                }
            }
        }
    }

    // MARK: - v2.43 Paralelo: ensure / sync / cleanup

    /// Asegura que el paralelo esté cargado con el ytId actual. Llama cada vez
    /// que cambia la canción (playTrack/next/prev).
    private func ensureParallelLoaded() {
        guard let track = state.currentTrack,
              let ytId = track.youtubeId, !ytId.isEmpty else { return }
        if parallelLoadedYtId == ytId { return }  // ya cargado

        if let cached = YouTubeExtractor.shared.cachedURL(for: ytId) {
            spawnParallel(url: cached, ytId: ytId, startAt: 0, audible: inBackground)
        } else {
            Task { @MainActor in
                do {
                    let url = try await YouTubeExtractor.shared.extractStreamURL(videoID: ytId, timeoutSec: 5)
                    // Verificar que el track no haya cambiado mientras tanto
                    guard self.state.currentTrack?.youtubeId == ytId else { return }
                    self.spawnParallel(url: url, ytId: ytId, startAt: 0, audible: self.inBackground)
                } catch {
                    if let purl = URL(string: "https://temazo.es/api/yt_proxy.php?id=\(ytId)") {
                        guard self.state.currentTrack?.youtubeId == ytId else { return }
                        self.spawnParallel(url: purl, ytId: ytId, startAt: 0, audible: self.inBackground)
                    }
                }
            }
        }
    }

    /// Crea (o reemplaza) el AVPlayer paralelo con la URL dada.
    /// audible=true → volumen 1 (estamos en bg). audible=false → volumen 0 (fg).
    private func spawnParallel(url: URL, ytId: String, startAt: Float, audible: Bool) {
        // Limpiar el paralelo anterior si existe
        cleanupParallel()

        let item = AVPlayerItem(url: url)
        let avp = AVPlayer(playerItem: item)
        avp.automaticallyWaitsToMinimizeStalling = false
        avp.volume = audible ? 1.0 : 0.0

        if startAt > 1 {
            let cm = CMTime(seconds: Double(startAt), preferredTimescale: 600)
            avp.seek(to: cm, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
        // play() siempre — el paralelo está corriendo siempre que isPlaying=true.
        if state.isPlaying { avp.play() }

        // Auto-next cuando termine el item (importante en bg para cadena de canciones)
        parallelEndObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }

        // Time observer SOLO para mantener state.positionSec actualizado en bg.
        // En fg el iframe es el master del tiempo via engine.onTime.
        parallelTimeObs = avp.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] t in
            guard let self else { return }
            if self.inBackground {
                self.state.positionSec = Float(t.seconds)
            }
        }

        parallelPlayer = avp
        parallelItem = item
        parallelLoadedYtId = ytId
        print("[Player] parallel armed videoId=\(ytId) audible=\(audible) startAt=\(startAt)")
    }

    private func cleanupParallel() {
        if let obs = parallelEndObs { NotificationCenter.default.removeObserver(obs); parallelEndObs = nil }
        if let obs = parallelTimeObs, let avp = parallelPlayer { avp.removeTimeObserver(obs); parallelTimeObs = nil }
        parallelPlayer?.pause()
        parallelPlayer?.replaceCurrentItem(with: nil)
        parallelPlayer = nil
        parallelItem = nil
        parallelLoadedYtId = nil
    }

    /// Sincroniza el paralelo con el iframe si hay drift > 1s.
    /// Llamado desde engine.onTime (cada 500ms).
    private func syncParallelToIframe(iframePos: Float) {
        guard !inBackground, let avp = parallelPlayer else { return }
        let parallelPos = Float(avp.currentTime().seconds)
        let drift = abs(iframePos - parallelPos)
        if drift > 1.0 {
            let cm = CMTime(seconds: Double(iframePos), preferredTimescale: 600)
            avp.seek(to: cm, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
    }

    // MARK: - Engine wiring

    private func wireEngine() {
        engine.onReady = { [weak self] in
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
                AudioSessionManager.shared.startSilentLoop()
                // Si el paralelo estaba pausado (carga inicial), arrancarlo
                if let avp = self.parallelPlayer, avp.rate == 0 { avp.play() }
            case "paused":
                if !self.state.isPlaying {
                    // pausa real del user → ya pausamos el paralelo en pause()
                } else {
                    print("[Player] iframe paused (iOS auto) — watchdog JS recuperará")
                }
            case "buffering":
                self.state.loadingState = .extracting
            case "ended":
                if !self.didAutoNext {
                    self.didAutoNext = true
                    self.next()
                }
            default: break
            }
        }

        engine.onError = { [weak self] code in
            self?.state.lastError = "yt error \(code)"
            self?.state.loadingState = .failed
            if code == 150 || code == 101 { self?.next() }
        }

        engine.onTime = { [weak self] pos, dur in
            guard let self else { return }
            // En foreground el iframe es el master del tiempo
            if !self.inBackground {
                self.state.positionSec = pos
                if dur > 0 { self.state.durationSec = dur }
                // Sync continuo del paralelo
                self.syncParallelToIframe(iframePos: pos)
            }
            // Auto-next manual de seguridad
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
        state.durationSec = Float(track.durationSec ?? 0)
        state.lastError = nil
        state.loadingState = .extracting
        didAutoNext = false
        AudioSessionManager.shared.ensureActive()
        startCurrentTrack()
        Task { try? await TemazoAPI.shared.historyAdd(track.id) }
    }

    /// Arranca el track actual en AMBOS motores. iframe = audible, AVPlayer paralelo = muted.
    private func startCurrentTrack() {
        guard let track = state.currentTrack,
              let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"
            state.loadingState = .failed
            return
        }
        state.isPlaying = true
        engine.play(videoId: ytId)
        // Prefetch del extractor para el current y los siguientes 3 tracks
        YouTubeExtractor.shared.prefetch(videoIDs: [ytId])
        prewarmNextExtractor()
        // Cargar el paralelo (volumen 0 en fg, 1 en bg)
        ensureParallelLoaded()
    }

    private func prewarmNextExtractor() {
        guard !state.queue.isEmpty else { return }
        var ids: [String] = []
        for offset in 1...3 {
            let idx = (state.index + offset) % state.queue.count
            if let yt = state.queue[idx].youtubeId, !yt.isEmpty, !ids.contains(yt) {
                ids.append(yt)
            }
            if state.queue.count <= offset { break }
        }
        if !ids.isEmpty { YouTubeExtractor.shared.prefetch(videoIDs: ids) }
    }

    func toggleRepeat() { state.repeatMode = (state.repeatMode + 1) % 3 }

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
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        // Resume AMBOS motores. El que sea audible (iframe en fg, paralelo en bg)
        // suena; el otro corre muted.
        engine.resume()
        parallelPlayer?.play()
    }

    func pause() {
        print("[Player] pause() called")
        state.isPlaying = false
        engine.pause()
        parallelPlayer?.pause()
        if !inBackground {
            AudioSessionManager.shared.stopSilentLoop()
        }
    }

    func addToQueue(_ track: Track) {
        if state.queue.contains(where: { $0.id == track.id }) { return }
        state.queue.append(track)
    }

    func next() {
        guard !state.queue.isEmpty else { return }

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
        // Seek en AMBOS motores para mantener sync
        engine.seek(toSec: seconds)
        if let avp = parallelPlayer {
            let cm = CMTime(seconds: Double(seconds), preferredTimescale: 600)
            avp.seek(to: cm, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
        state.positionSec = seconds
    }

    func stopAll() {
        engine.stop()
        cleanupParallel()
        AudioSessionManager.shared.stopSilentLoop()
        state = PlayerState()
    }

    func setCrossfadeMs(_ ms: Int) { crossfadeMs = max(150, min(6000, ms)) }
}
