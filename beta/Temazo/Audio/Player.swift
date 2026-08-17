import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer

/// Player nativo basado en AVPlayer.
/// La URL del stream YouTube se obtiene del proxy de temazo.es:
///   https://temazo.es/api/yt_proxy.php?id=<youtube_id>
/// El backend usa yt-dlp para resolver y reenviar bytes (bypaseando IP-binding de YouTube).
///
/// Resultado: AVPlayer reproduce un stream desde temazo.es → background audio funciona
/// nativamente, igual que Spotify/Apple Music.
/// Backend activo para la reproducción del track actual.
///  - webView: WKWebView + iframe YouTube (default, instant, sin proxy)
///  - avPlayer: AVPlayer clásico (fallback cuando el video bloquea embed
///    o cuando hay descarga offline local)
enum PlayerBackend: String {
    case webView
    case avPlayer
}

@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private static let proxyBase = "https://temazo.es/api/yt_proxy.php"

    /// Backend actualmente reproduciendo. Se establece en startPlayback y se usa
    /// para dispatch de play/pause/seek/etc al player correcto.
    private var backend: PlayerBackend = .webView

    private var avPlayer: AVPlayer?
    private var statusObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private var stallObs: NSObjectProtocol?
    private var crossfadeMs: Int = 250
    /// Flag para evitar doble next() entre AVPlayerItemDidPlayToEndTime y nuestro
    /// detector manual via positionSec ≥ durationSec - 0.4s.
    private var didAutoNext: Bool = false

    /// v1.2.43: contador de intentos WebView por track. Si el iframe reporta
    /// error 101/150 (embed disabled), no reintentamos infinito — pasamos a
    /// AVPlayer + yt_proxy inmediatamente.
    private var webViewAttempts: [String: Int] = [:]

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        setupWebViewCallbacks()
    }

    /// Registra los callbacks del YouTubeWebPlayer una sola vez. Los eventos
    /// del iframe (state change, error, ended, current time) se traducen a
    /// mutaciones de `PlayerState` idénticas a las que hace el observer de AVPlayer.
    private func setupWebViewCallbacks() {
        let yt = YouTubeWebPlayer.shared

        yt.onStateChange = { [weak self] s in
            guard let self else { return }
            // YT.PlayerState: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
            switch s {
            case 1:
                self.state.isPlaying = true
                self.state.ready = true
                self.state.loadingState = .playing
            case 2:
                self.state.isPlaying = false
            case 3:
                self.state.loadingState = .stalled  // buffering visualmente = stalled
            case 5:
                self.state.loadingState = .ready
            case 0:
                self.state.isPlaying = false
                self.state.loadingState = .ready
            default:
                break
            }
        }

        yt.onError = { [weak self] code in
            guard let self else { return }
            // Solo actuamos si el error es del track ACTUALMENTE reproduciéndose
            // en modo webView (no de un load stale que llegó tarde).
            guard self.backend == .webView,
                  let track = self.state.currentTrack,
                  let yt = track.youtubeId,
                  YouTubeWebPlayer.shared.currentVideoId == yt else { return }

            print("[Player] webView error code=\(code) for \(yt) → fallback AVPlayer")
            // Fallback inmediato al AVPlayer + yt_proxy. Marcamos el track como
            // "intentado en webView" para no volver a intentarlo esta sesión.
            self.webViewAttempts[yt] = (self.webViewAttempts[yt] ?? 0) + 1
            self.startAVPlayback(for: track)
        }

        yt.onEnded = { [weak self] in
            guard let self, self.backend == .webView else { return }
            if !self.didAutoNext {
                self.didAutoNext = true
                self.next()
            }
        }

        yt.onCurrentTime = { [weak self] cur, dur in
            guard let self, self.backend == .webView else { return }
            self.state.positionSec = Float(cur)
            if dur > 0.5 {
                self.state.durationSec = Float(dur)
            }
        }
    }

    func playTrack(_ track: Track, queue: [Track], index: Int, source: String? = nil) {
        state.queue = queue
        state.index = index
        state.currentTrack = track
        state.positionSec = 0
        state.source = source
        // Duración del backend = source of truth (yt-dlp/AVAsset a veces reporta x2 por
        // headers del proxy o contenedor sin metadata de duración fiable).
        state.durationSec = Float(track.durationSec ?? 0)
        state.lastError = nil
        state.loadingState = .extracting
        didAutoNext = false
        AudioSessionManager.shared.ensureActive()
        startPlayback(for: track)
        prewarmNext()
        Task { try? await TemazoAPI.shared.historyAdd(track.id) }
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
        switch backend {
        case .webView: YouTubeWebPlayer.shared.play()
        case .avPlayer: avPlayer?.play()
        }
        state.isPlaying = true
    }

    func pause() {
        print("[Player] pause() called backend=\(backend.rawValue)")
        switch backend {
        case .webView: YouTubeWebPlayer.shared.pause()
        case .avPlayer: avPlayer?.pause()
        }
        state.isPlaying = false
    }

    /// Añade un track al final de la cola actual sin interrumpir reproducción.
    func addToQueue(_ track: Track) {
        if state.queue.contains(where: { $0.id == track.id }) { return }
        state.queue.append(track)
    }

    func next() {
        guard !state.queue.isEmpty else { return }

        // REPEAT_ONE: recargar misma canción
        if state.repeatMode == 2, state.index >= 0, state.index < state.queue.count {
            let t = state.queue[state.index]
            state.currentTrack = t
            state.positionSec = 0
            state.durationSec = Float(t.durationSec ?? 0)
            state.loadingState = .extracting
            didAutoNext = false
            startPlayback(for: t)
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
        startAVPlayback(for: t)
        prewarmNext()
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
        startAVPlayback(for: t)
        prewarmNext()
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    /// Pre-resuelve URLs de los próximos 5 tracks. Dos canales:
    ///  1) YouTubeExtractor (iPhone) → URL directa googlevideo cacheada localmente
    ///  2) Backend yt_resolve.php → para fallback proxy
    /// El play de next() es casi instantáneo si la URL ya está en el cache.
    private func prewarmNext() {
        guard !state.queue.isEmpty else { return }
        var ids: [String] = []
        for offset in 1...5 {
            let idx = (state.index + offset) % state.queue.count
            if let yt = state.queue[idx].youtubeId, !yt.isEmpty, !ids.contains(yt) {
                ids.append(yt)
            }
            if state.queue.count <= offset { break }
        }
        if !ids.isEmpty {
            // Canal 1 — iPhone extrae la URL directa de googlevideo (rápido)
            YouTubeExtractor.shared.prefetch(videoIDs: ids)
            // Canal 2 — backend calienta su cache (por si extractor falla)
            TemazoAPI.shared.prefetchYouTubeURLs(ids)
        }
    }

    func seekTo(seconds: Float) {
        switch backend {
        case .webView:
            YouTubeWebPlayer.shared.seek(seconds: Double(seconds))
        case .avPlayer:
            guard let p = avPlayer else { return }
            let cm = CMTime(seconds: Double(seconds), preferredTimescale: 600)
            p.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        state.positionSec = seconds
    }

    func stopAll() {
        teardownObservers()
        YouTubeWebPlayer.shared.stop()
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
        state = PlayerState()
    }

    func setCrossfadeMs(_ ms: Int) { crossfadeMs = max(150, min(6000, ms)) }

    // MARK: - Dispatcher (v1.2.43: WebView first, AVPlayer fallback)

    /// Estrategia v1.2.43:
    ///   1. Si hay archivo offline descargado → AVPlayer local (preserves feature)
    ///   2. Sino → WebView iframe YouTube (instant, sin proxy)
    ///   3. Si WebView reporta embed disabled (101/150) → callback dispara startAVPlayback
    ///      → AVPlayer + yt_proxy como fallback silencioso
    private func startPlayback(for track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"; state.loadingState = .failed
            print("[Player] no youtubeId for track id=\(track.id)"); return
        }

        // Path 1: offline local (mantiene AVPlayer + AirPlay + calidad garantizada)
        if let localURL = OfflineLibrary.shared.localURL(for: ytId) {
            print("[Player] offline hit \(ytId)")
            backend = .avPlayer
            startWithURL(localURL, track: track, source: "offline-download")
            return
        }

        // Path 2: si este track ya falló antes en WebView (embed disabled) esta sesión,
        // no volvemos a intentar iframe — directamente a AVPlayer + yt_proxy.
        if (webViewAttempts[ytId] ?? 0) > 0 {
            print("[Player] webView previously failed for \(ytId) → AVPlayer directo")
            startAVPlayback(for: track)
            return
        }

        // Path 3 (default v1.2.43): WebView iframe YouTube — instant.
        // Si el iframe reporta error 101/150, el callback onError disparará
        // startAVPlayback automáticamente para este track.
        backend = .webView
        // Pausar AVPlayer si venía sonando de un track previo por AVPlayer
        avPlayer?.pause()
        teardownObservers()
        state.loadingState = .extracting
        state.source = "webview-iframe"
        YouTubeWebPlayer.shared.load(videoId: ytId, autoplay: true)
    }

    // MARK: - AVPlayer streaming (fallback + offline)

    private func startAVPlayback(for track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"; state.loadingState = .failed
            print("[Player] no youtubeId for track id=\(track.id)"); return
        }

        backend = .avPlayer
        // Silenciar WebView si venía sonando
        YouTubeWebPlayer.shared.stop()

        // BETA v1.2.19: PRIORIDAD MÁXIMA archivo local descargado.
        if let localURL = OfflineLibrary.shared.localURL(for: ytId) {
            print("[Player] offline hit \(ytId)")
            startWithURL(localURL, track: track, source: "offline-download")
            return
        }

        // Estrategia clásica AVPlayer (fallback cuando WebView falla):
        //   1. Cache hit del extractor → instantáneo
        //   2. Esperar al extractor live (timeout 8s)
        //   3. Si extractor falla → fallback al proxy yt_proxy (lento pero funciona)

        if let cached = YouTubeExtractor.shared.cachedURL(for: ytId) {
            startWithURL(cached, track: track, source: "extractor-cache")
            TemazoAPI.shared.prefetchYouTubeURLs([ytId])
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let stillCurrent = { self.state.currentTrack?.id == track.id }

            if let directURL = try? await YouTubeExtractor.shared.extractStreamURL(
                videoID: ytId, timeoutSec: 8
            ), stillCurrent() {
                self.startWithURL(directURL, track: track, source: "extractor-live")
                TemazoAPI.shared.prefetchYouTubeURLs([ytId])
                return
            }

            guard stillCurrent() else { return }
            guard let proxyURL = self.buildProxyURL(ytId: ytId) else {
                self.state.lastError = "no url"; self.state.loadingState = .failed
                return
            }
            self.startWithURL(proxyURL, track: track, source: "proxy-302-fallback")
            TemazoAPI.shared.prefetchYouTubeURLs([ytId])
        }
    }

    private func startWithURL(_ url: URL, track: Track, source: String) {
        teardownObservers()
        print("[Player] streaming from \(source): \(url.absoluteString.prefix(80))…")

        // CRÍTICO: activar AudioSession ANTES de crear el AVPlayer.
        // Sin esto, en ciertos estados iOS el audio NO sale por altavoz aunque
        // el player toque (bug "no se escucha" reportado).
        AudioSessionManager.shared.ensureActive()

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TemazoApp/1.0"
            ]
        ])
        let item = AVPlayerItem(asset: asset)
        // Buffer mínimo 4s → empieza a sonar rápido. Si stalls, el observer .stalled
        // los gestiona. Total = ~80% menos de espera vs el comportamiento por defecto.
        item.preferredForwardBufferDuration = 4

        let p = AVPlayer(playerItem: item)
        // false = empezar lo antes posible. Antes era true (espera buffer grande).
        p.automaticallyWaitsToMinimizeStalling = false
        p.allowsExternalPlayback = false
        p.actionAtItemEnd = .none
        avPlayer = p

        // Log estado de la audio session
        let s = AVAudioSession.sharedInstance()
        print("[Player] AudioSession.category=\(s.category) mode=\(s.mode)")

        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    // Solo escribir desde AVAsset si NO tenemos duración del backend.
                    // El backend es la fuente fiable; el AVAsset a veces reporta x2.
                    if self.state.durationSec == 0,
                       let d = item.asset.duration as CMTime?,
                       d.isValid && !d.isIndefinite {
                        self.state.durationSec = Float(CMTimeGetSeconds(d))
                    }
                    self.state.ready = true
                    self.state.loadingState = .ready
                    print("[Player] readyToPlay duration=\(self.state.durationSec)s")
                case .failed:
                    let err = item.error?.localizedDescription ?? "unknown"
                    self.state.lastError = err
                    self.state.loadingState = .failed
                    print("[Player] item FAILED: \(err)")
                case .unknown: break
                @unknown default: break
                }
            }
        }

        rateObs = p.observe(\.rate, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if p.rate > 0 {
                    self.state.loadingState = .playing
                    self.state.isPlaying = true
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObs = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cm in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let pos = Float(CMTimeGetSeconds(cm))
                self.state.positionSec = pos
                if self.state.durationSec == 0,
                   let d = self.avPlayer?.currentItem?.duration,
                   d.isValid && !d.isIndefinite {
                    self.state.durationSec = Float(CMTimeGetSeconds(d))
                }
                // Auto-next manual: si AVPlayerItemDidPlayToEndTime no dispara
                // (proxy sin Content-Length, stream truncado, etc), detectamos
                // el fin via posición ≥ duración - 0.4s y avanzamos.
                if self.state.durationSec > 1,
                   pos >= self.state.durationSec - 0.4,
                   self.state.isPlaying,
                   !self.didAutoNext {
                    self.didAutoNext = true
                    self.next()
                }
            }
        }

        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.didAutoNext {
                    self.didAutoNext = true
                    self.next()
                }
            }
        }

        stallObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state.loadingState = .stalled
                print("[Player] stalled")
            }
        }

        AudioSessionManager.shared.ensureActive()
        p.play()
        state.isPlaying = true
    }

    private func buildProxyURL(ytId: String) -> URL? {
        var comps = URLComponents(string: Self.proxyBase)
        var items = [URLQueryItem(name: "id", value: ytId)]
        // v6 backend: si enviamos ?next=id1,id2,id3 el proxy pre-descarga esos
        // tracks en background tras servir el actual → siguientes tracks
        // cache-hit (~0.1s) cuando el user pulsa siguiente.
        let nextIds = nextQueuedYoutubeIds(count: 3)
        if !nextIds.isEmpty {
            items.append(URLQueryItem(name: "next", value: nextIds.joined(separator: ",")))
        }
        comps?.queryItems = items
        return comps?.url
    }

    /// Devuelve los youtube_id de los próximos N tracks de la cola actual
    /// (partiendo del índice actual + 1). Skip tracks sin youtube_id.
    /// Con repeatMode==1 (playlist en loop) puede envolver una vez al principio.
    private func nextQueuedYoutubeIds(count: Int) -> [String] {
        var out: [String] = []
        let q = state.queue
        guard !q.isEmpty, count > 0 else { return out }
        // Máx pasos = q.count (evita loops infinitos con listas sin youtube_id)
        for offset in 1...q.count {
            var idx = state.index + offset
            if idx >= q.count {
                if state.repeatMode == 1 {
                    idx = idx % q.count
                } else {
                    break
                }
            }
            if let yt = q[idx].youtubeId, yt.count == 11 {
                out.append(yt)
                if out.count >= count { break }
            }
        }
        return out
    }

    private func teardownObservers() {
        statusObs?.invalidate(); statusObs = nil
        rateObs?.invalidate(); rateObs = nil
        if let obs = timeObs { avPlayer?.removeTimeObserver(obs); timeObs = nil }
        if let obs = endObs { NotificationCenter.default.removeObserver(obs); endObs = nil }
        if let obs = stallObs { NotificationCenter.default.removeObserver(obs); stallObs = nil }
    }
}
