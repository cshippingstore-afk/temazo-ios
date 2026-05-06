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

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    func playTrack(_ track: Track, queue: [Track], index: Int) {
        state.queue = queue
        state.index = index
        state.currentTrack = track
        state.positionSec = 0
        state.durationSec = 0
        state.lastError = nil
        state.loadingState = .extracting
        AudioSessionManager.shared.ensureActive()
        startAVPlayback(for: track)
        Task { try? await TemazoAPI.shared.historyAdd(track.id) }
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

    func next() {
        guard !state.queue.isEmpty else { return }
        let nextIdx = (state.index + 1) % state.queue.count
        let t = state.queue[nextIdx]
        state.index = nextIdx
        state.currentTrack = t
        state.loadingState = .extracting
        startAVPlayback(for: t)
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func prev() {
        guard !state.queue.isEmpty else { return }
        let prevIdx = state.index <= 0 ? state.queue.count - 1 : state.index - 1
        let t = state.queue[prevIdx]
        state.index = prevIdx
        state.currentTrack = t
        state.loadingState = .extracting
        startAVPlayback(for: t)
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
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
        guard let proxyURL = buildProxyURL(ytId: ytId) else {
            state.lastError = "invalid proxy URL"; state.loadingState = .failed
            return
        }
        teardownObservers()

        print("[Player] streaming from \(proxyURL.absoluteString)")
        let item = AVPlayerItem(url: proxyURL)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
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
                    if let d = item.asset.duration as CMTime?,
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
                self.state.positionSec = Float(CMTimeGetSeconds(cm))
                if self.state.durationSec == 0,
                   let d = self.avPlayer?.currentItem?.duration,
                   d.isValid && !d.isIndefinite {
                    self.state.durationSec = Float(CMTimeGetSeconds(d))
                }
            }
        }

        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.next() }
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
