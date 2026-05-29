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
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private static let proxyBase = "https://temazo.es/api/yt_proxy.php"

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

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
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
        startAVPlayback(for: track)
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
        avPlayer?.play()
        state.isPlaying = true
    }

    func pause() {
        print("[Player] pause() called")
        avPlayer?.pause()
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
            startAVPlayback(for: t)
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
        guard let p = avPlayer else { return }
        let cm = CMTime(seconds: Double(seconds), preferredTimescale: 600)
        p.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        state.positionSec = seconds
    }

    func stopAll() {
        teardownObservers()
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
        state = PlayerState()
    }

    func setCrossfadeMs(_ ms: Int) { crossfadeMs = max(150, min(6000, ms)) }

    // MARK: - AVPlayer streaming desde el proxy backend

    private func startAVPlayback(for track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"; state.loadingState = .failed
            print("[Player] no youtubeId for track id=\(track.id)"); return
        }

        // Estrategia: cache hit del extractor → URL directa googlevideo (instantáneo).
        // Si no, ir directo al proxy temazo.es?id=X (302 redirect ya configurado).
        // NO esperar al extractor: muchas canciones populares tienen signatureCipher
        // y el extractor falla — perderíamos segundos en vano. Mejor probar proxy ya
        // y dejar el extractor corriendo en background para futuros plays.
        //
        // TODO v2.21: Migrar a WKWebView + iframe oficial YouTube (igual que Android).
        // El proxy actual está rate-limited por YouTube (29 KB/s) porque todos los
        // users comparten la IP del VPS. WKWebView usa la IP del dispositivo del
        // user → sin throttle. `_app_player.html` ya está preparado con el bridge
        // webkit.messageHandlers.player. Es un refactor grande, se hace aparte.
        if let cached = YouTubeExtractor.shared.cachedURL(for: ytId) {
            startWithURL(cached, track: track, source: "extractor-cache")
            // Calienta también para próxima vez
            TemazoAPI.shared.prefetchYouTubeURLs([ytId])
            return
        }

        guard let proxyURL = buildProxyURL(ytId: ytId) else {
            state.lastError = "no url"; state.loadingState = .failed
            return
        }
        startWithURL(proxyURL, track: track, source: "proxy-302")

        // Background: warmer del backend + intento del extractor para próxima vez
        TemazoAPI.shared.prefetchYouTubeURLs([ytId])
        Task.detached { _ = try? await YouTubeExtractor.shared.extractStreamURL(videoID: ytId, timeoutSec: 8) }
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
        comps?.queryItems = [URLQueryItem(name: "id", value: ytId)]
        return comps?.url
    }

    private func teardownObservers() {
        statusObs?.invalidate(); statusObs = nil
        rateObs?.invalidate(); rateObs = nil
        if let obs = timeObs { avPlayer?.removeTimeObserver(obs); timeObs = nil }
        if let obs = endObs { NotificationCenter.default.removeObserver(obs); endObs = nil }
        if let obs = stallObs { NotificationCenter.default.removeObserver(obs); stallObs = nil }
    }
}
