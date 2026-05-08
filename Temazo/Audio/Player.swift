import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer

/// Player con AVQueuePlayer + pre-buffering del siguiente track para cambios instantáneos.
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private static let proxyBase = "https://temazo.es/api/yt_proxy.php"

    private var queuePlayer: AVQueuePlayer?
    private var statusObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var currentItemObs: NSKeyValueObservation?
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private var stallObs: NSObjectProtocol?
    private var crossfadeMs: Int = 250

    /// Item pre-bufferado del siguiente track (no aún en queue, listo para insertar)
    private var nextPreloadedItem: AVPlayerItem?
    private var nextPreloadedTrackId: Int64?

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    func playTrack(_ track: Track, queue: [Track], index: Int) {
        state.queue = queue
        state.index = index
        state.currentTrack = track
        state.positionSec = 0
        // Inicializar con la duración real del backend (YouTube metadata).
        // El manifest HLS de YouTube a veces infla este valor; preferimos siempre
        // la del backend cuando esté disponible.
        state.durationSec = Float(track.durationSec ?? 0)
        state.lastError = nil
        state.loadingState = .extracting
        AudioSessionManager.shared.ensureActive()
        startPlayback(track: track)
        prefetchUpcoming()
    }

    func togglePlay() { if state.isPlaying { pause() } else { resume() } }

    func resume() {
        AudioSessionManager.shared.ensureActive()
        queuePlayer?.play()
        state.isPlaying = true
    }

    func pause() {
        queuePlayer?.pause()
        state.isPlaying = false
    }

    func next() {
        guard !state.queue.isEmpty else { return }
        let nextIdx = (state.index + 1) % state.queue.count
        let t = state.queue[nextIdx]
        state.index = nextIdx
        state.currentTrack = t

        // Si el item ya está pre-bufferado, swap instantáneo
        if let preloaded = nextPreloadedItem,
           nextPreloadedTrackId == t.id,
           let qp = queuePlayer {
            print("[Player] next() using PRELOADED item for track \(t.id)")
            attachItemObservers(preloaded)
            qp.removeAllItems()
            qp.insert(preloaded, after: nil)
            nextPreloadedItem = nil
            nextPreloadedTrackId = nil
            qp.play()
            state.loadingState = .ready
            state.isPlaying = true
        } else {
            state.loadingState = .extracting
            startPlayback(track: t)
        }
        prefetchUpcoming()
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func prev() {
        guard !state.queue.isEmpty else { return }
        let prevIdx = state.index <= 0 ? state.queue.count - 1 : state.index - 1
        let t = state.queue[prevIdx]
        state.index = prevIdx
        state.currentTrack = t
        state.loadingState = .extracting
        startPlayback(track: t)
        prefetchUpcoming()
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func seekTo(seconds: Float) {
        guard let p = queuePlayer else { return }
        let cm = CMTime(seconds: Double(seconds), preferredTimescale: 600)
        p.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        state.positionSec = seconds
    }

    func stopAll() {
        teardownObservers()
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        nextPreloadedItem = nil
        nextPreloadedTrackId = nil
        state = PlayerState()
    }

    func setCrossfadeMs(_ ms: Int) { crossfadeMs = max(150, min(6000, ms)) }

    // MARK: - Playback

    private func startPlayback(track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"; state.loadingState = .failed; return
        }
        Task { await self.resolveAndPlay(track: track, ytId: ytId) }
    }

    private func resolveAndPlay(track: Track, ytId: String) async {
        // 1. Intento extracción directa con WKWebView (URL → YouTube CDN, IP del iPhone, RÁPIDO)
        var streamURL: URL?
        do {
            let url = try await YouTubeExtractor.shared.extractStreamURL(videoID: ytId, timeoutSec: 5)
            streamURL = url
            print("[Player] DIRECT URL ok for \(ytId)")
        } catch {
            print("[Player] direct extract failed (\(error.localizedDescription)) → fallback proxy")
        }
        // 2. Fallback: proxy backend (siempre funciona pero más lento)
        if streamURL == nil {
            streamURL = proxyURL(for: track)
        }
        guard let url = streamURL else {
            state.lastError = "no url"; state.loadingState = .failed; return
        }
        startAVPlayer(track: track, url: url)
    }

    private func startAVPlayer(track: Track, url: URL) {
        teardownObservers()
        let item = makePlayerItem(url: url)
        attachItemObservers(item)

        if let qp = queuePlayer {
            qp.removeAllItems()
            qp.insert(item, after: nil)
        } else {
            let qp = AVQueuePlayer(items: [item])
            qp.automaticallyWaitsToMinimizeStalling = false
            qp.allowsExternalPlayback = false
            qp.actionAtItemEnd = .advance
            queuePlayer = qp
            attachPlayerObservers(qp)
        }
        AudioSessionManager.shared.ensureActive()
        queuePlayer?.play()
        state.isPlaying = true
        state.loadingState = .playing  // ya empezamos, ocultar texto de estado
        print("[Player] startAVPlayer track=\(track.id) url=\(url.absoluteString.prefix(100))…")
    }

    private func makePlayerItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "Temazo iOS"],
        ])
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable", "duration"])
        item.preferredForwardBufferDuration = 4.0   // buffer mínimo de 4s antes de empezar
        return item
    }

    private func proxyURL(for track: Track) -> URL? {
        guard let ytId = track.youtubeId, !ytId.isEmpty else { return nil }
        var c = URLComponents(string: Self.proxyBase)
        c?.queryItems = [URLQueryItem(name: "id", value: ytId)]
        return c?.url
    }

    // MARK: - Pre-fetch

    /// Pre-resolve URLs en backend para los próximos tracks (no descarga bytes,
    /// solo cachea la URL en el server). Y pre-buffer el item del siguiente track.
    private func prefetchUpcoming() {
        guard !state.queue.isEmpty else { return }
        let count = state.queue.count
        // Resolve URLs de los próximos 5 tracks en backend (cache hot)
        var ids: [String] = []
        for offset in 1...min(5, count - 1) {
            let i = (state.index + offset) % count
            if let id = state.queue[i].youtubeId, !id.isEmpty { ids.append(id) }
        }
        if !ids.isEmpty {
            print("[Player] prefetching \(ids.count) URLs in backend")
            TemazoAPI.shared.prefetchYouTubeURLs(ids)
        }

        // Pre-buffer el item del siguiente track (N+1)
        let nextIdx = (state.index + 1) % count
        guard nextIdx != state.index else { return }
        let nextTrack = state.queue[nextIdx]
        if nextPreloadedTrackId == nextTrack.id {
            return  // ya pre-cargado
        }
        if let url = proxyURL(for: nextTrack) {
            print("[Player] pre-buffering next track \(nextTrack.id)")
            let item = makePlayerItem(url: url)
            // Trigger asset loading
            item.asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {}
            nextPreloadedItem = item
            nextPreloadedTrackId = nextTrack.id
        }
    }

    // MARK: - Observers

    private func attachPlayerObservers(_ p: AVQueuePlayer) {
        rateObs = p.observe(\.rate, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if p.rate > 0 {
                    self.state.loadingState = .playing
                    self.state.isPlaying = true
                }
            }
        }

        currentItemObs = p.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.handleItemAdvance() }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObs = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cm in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let pos = Float(CMTimeGetSeconds(cm))
                self.state.positionSec = pos
                if self.state.durationSec == 0,
                   let d = self.queuePlayer?.currentItem?.duration,
                   d.isValid && !d.isIndefinite {
                    self.state.durationSec = Float(CMTimeGetSeconds(d))
                }
                // Si conocemos la duración REAL del track (backend) y el manifest
                // de YouTube dura más, AVPlayer no dispara DidPlayToEndTime al
                // acabar la música — forzamos la transición al siguiente track.
                if self.state.isPlaying,
                   let real = self.state.currentTrack?.durationSec, real > 0,
                   pos >= Float(real) - 0.3 {
                    // Comparar con la duración del item: si es claramente mayor,
                    // adelantamos al siguiente. Tolerancia 5s para evitar falsos.
                    let manifestSec: Float = (self.queuePlayer?.currentItem?.duration).flatMap {
                        ($0.isValid && !$0.isIndefinite) ? Float(CMTimeGetSeconds($0)) : nil
                    } ?? 0
                    if manifestSec > Float(real) + 5 {
                        self.handleEnded()
                    }
                }
            }
        }
    }

    private func attachItemObservers(_ item: AVPlayerItem) {
        statusObs?.invalidate()
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    // Solo aceptar la duración del manifest si el backend NO proporcionó una.
                    // El manifest HLS de YouTube a veces sobreestima la duración real.
                    if self.state.durationSec == 0,
                       let d = item.asset.duration as CMTime?, d.isValid, !d.isIndefinite {
                        self.state.durationSec = Float(CMTimeGetSeconds(d))
                    }
                    self.state.ready = true
                    self.state.loadingState = .ready
                case .failed:
                    self.state.lastError = item.error?.localizedDescription ?? "load failed"
                    self.state.loadingState = .failed
                    print("[Player] item FAILED: \(self.state.lastError ?? "")")
                case .unknown: break
                @unknown default: break
                }
            }
        }
        if let prev = endObs { NotificationCenter.default.removeObserver(prev) }
        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleEnded() }
        }
        if let prev = stallObs { NotificationCenter.default.removeObserver(prev) }
        stallObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.state.loadingState = .stalled }
        }
    }

    private func handleEnded() {
        next()
    }

    private func handleItemAdvance() {
        // si AVQueuePlayer avanzó solo, sincronizar state.index
        // (ya se gestiona via handleEnded → next())
    }

    private func teardownObservers() {
        statusObs?.invalidate(); statusObs = nil
        rateObs?.invalidate(); rateObs = nil
        currentItemObs?.invalidate(); currentItemObs = nil
        if let obs = timeObs { queuePlayer?.removeTimeObserver(obs); timeObs = nil }
        if let obs = endObs { NotificationCenter.default.removeObserver(obs); endObs = nil }
        if let obs = stallObs { NotificationCenter.default.removeObserver(obs); stallObs = nil }
    }
}
