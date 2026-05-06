import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer
import YouTubeKit

@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private var avPlayer: AVPlayer?
    private var statusObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private var stallObs: NSObjectProtocol?
    private var crossfadeMs: Int = 250
    private var loadingTaskID: UUID?

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
        state.loadingState = .extracting
        state.lastError = nil
        AudioSessionManager.shared.ensureActive()
        Task { await loadAndPlay(track) }
        Task { try? await TemazoAPI.shared.historyAdd(track.id) }
    }

    func togglePlay() {
        if state.isPlaying { pause() } else { resume() }
    }

    func resume() {
        AudioSessionManager.shared.ensureActive()
        avPlayer?.play()
        state.isPlaying = true
    }

    func pause() {
        print("[Player] pause() called from \(Thread.callStackSymbols.prefix(4).joined(separator: " | "))")
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
        Task { await loadAndPlay(t) }
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func prev() {
        guard !state.queue.isEmpty else { return }
        let prevIdx = state.index <= 0 ? state.queue.count - 1 : state.index - 1
        let t = state.queue[prevIdx]
        state.index = prevIdx
        state.currentTrack = t
        state.loadingState = .extracting
        Task { await loadAndPlay(t) }
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

    func setCrossfadeMs(_ ms: Int) {
        crossfadeMs = max(150, min(6000, ms))
    }

    // MARK: - Carga via YouTubeKit + AVPlayer

    private func loadAndPlay(_ track: Track) async {
        guard let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"; state.loadingState = .failed
            print("[Player] no youtubeId, skip"); next(); return
        }
        let myTask = UUID()
        loadingTaskID = myTask
        print("[Player] extracting URL for ytId=\(ytId)")

        do {
            let yt = YouTube(videoID: ytId)
            let streams = try await yt.streams
            print("[Player] YouTubeKit returned \(streams.count) streams")

            let chosen: YouTubeKit.Stream? =
                streams.filterAudioOnly().highestAudioBitrateStream()
                ?? streams.filter { $0.includesAudioTrack }.lowestResolutionStream()
                ?? streams.filter { $0.includesAudioTrack }.first
                ?? streams.first

            guard let stream = chosen else {
                state.lastError = "no playable stream"; state.loadingState = .failed
                print("[Player] no playable stream for \(ytId)"); next(); return
            }
            guard loadingTaskID == myTask else { return }
            print("[Player] chosen stream: itag=\(stream.itag) audioOnly=\(!stream.includesVideoTrack) url=\(stream.url.absoluteString.prefix(120))…")
            await MainActor.run { self.startAVPlayback(streamURL: stream.url, trackTitle: track.title) }
        } catch {
            state.lastError = "extract: \(error.localizedDescription)"
            state.loadingState = .failed
            print("[Player] YouTubeKit error: \(error)")
            // No avanzamos automáticamente — para que el usuario vea el error en pantalla
        }
    }

    private func startAVPlayback(streamURL: URL, trackTitle: String) {
        teardownObservers()
        let item = AVPlayerItem(url: streamURL)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true   // permitir buffering correcto en background
        p.allowsExternalPlayback = false
        p.actionAtItemEnd = .none
        avPlayer = p

        // Log audio session state
        let session = AVAudioSession.sharedInstance()
        print("[Player] AudioSession.category=\(session.category) active=\(session.isOtherAudioPlaying) outputVolume=\(session.outputVolume)")

        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let d = item.asset.duration
                    if d.isValid && !d.isIndefinite {
                        self.state.durationSec = Float(CMTimeGetSeconds(d))
                    }
                    self.state.ready = true
                    self.state.loadingState = .ready
                    print("[Player] item readyToPlay duration=\(self.state.durationSec)s")
                case .failed:
                    let err = item.error?.localizedDescription ?? "unknown"
                    self.state.lastError = "AVPlayer: \(err)"
                    self.state.loadingState = .failed
                    print("[Player] item FAILED: \(err)")
                case .unknown:
                    print("[Player] item unknown")
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
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.next() }
        }

        stallObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state.loadingState = .stalled
                print("[Player] stalled")
            }
        }

        AudioSessionManager.shared.ensureActive()
        p.play()
        state.isPlaying = true
        print("[Player] AVPlayer.play() invoked")
    }

    private func teardownObservers() {
        statusObs?.invalidate(); statusObs = nil
        rateObs?.invalidate(); rateObs = nil
        if let obs = timeObs { avPlayer?.removeTimeObserver(obs); timeObs = nil }
        if let obs = endObs { NotificationCenter.default.removeObserver(obs); endObs = nil }
        if let obs = stallObs { NotificationCenter.default.removeObserver(obs); stallObs = nil }
    }
}
