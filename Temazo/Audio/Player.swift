import Foundation
import AVFoundation
import Combine
import UIKit
import YouTubeKit

/// Player nativo basado en AVPlayer.
/// Usa YouTubeKit para extraer el stream URL del video YouTube → AVPlayer lo reproduce.
/// Background audio funciona NATIVAMENTE (sin tricks de WebView), igual que Spotify/Apple Music.
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()

    @Published var state = PlayerState()

    private var avPlayer: AVPlayer?
    private var statusObs: NSKeyValueObservation?
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private var crossfadeMs: Int = 250
    private var loadingTaskID: UUID?

    // MARK: - Public API

    func playTrack(_ track: Track, queue: [Track], index: Int) {
        state.queue = queue
        state.index = index
        state.currentTrack = track
        state.positionSec = 0
        state.durationSec = 0
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
        avPlayer?.pause()
        state.isPlaying = false
    }

    func next() {
        guard !state.queue.isEmpty else { return }
        let nextIdx = (state.index + 1) % state.queue.count
        let t = state.queue[nextIdx]
        state.index = nextIdx
        state.currentTrack = t
        Task { await loadAndPlay(t) }
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func prev() {
        guard !state.queue.isEmpty else { return }
        let prevIdx = state.index <= 0 ? state.queue.count - 1 : state.index - 1
        let t = state.queue[prevIdx]
        state.index = prevIdx
        state.currentTrack = t
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
            print("[Player] no youtubeId, skip")
            await MainActor.run { self.next() }
            return
        }

        let myTask = UUID()
        loadingTaskID = myTask
        state.ready = false

        // Extraer stream URL del YouTube ID
        do {
            let yt = YouTube(videoID: ytId)
            let streams = try await yt.streams
            // Preferir audio-only (mejor calidad/peso) → si no hay, mp4 con audio
            // Preferir audio-only highest bitrate; si no, mp4 con audio (cualquier resolución baja)
            let chosen: YouTubeKit.Stream? =
                streams.filterAudioOnly().highestAudioBitrateStream()
                ?? streams.filter { $0.includesAudioTrack }.lowestResolutionStream()
                ?? streams.filter { $0.includesAudioTrack }.first
                ?? streams.first
            guard let stream = chosen else {
                print("[Player] no stream available for \(ytId)")
                await MainActor.run { self.next() }
                return
            }
            // Si esta task ya no es la actual (track cambió), abandonamos
            guard loadingTaskID == myTask else { return }
            await MainActor.run { self.startAVPlayback(streamURL: stream.url) }
        } catch {
            print("[Player] YouTubeKit error for \(ytId): \(error)")
            await MainActor.run { self.next() }
        }
    }

    private func startAVPlayback(streamURL: URL) {
        teardownObservers()
        let item = AVPlayerItem(url: streamURL)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        p.allowsExternalPlayback = false
        avPlayer = p

        // Observa duración cuando el item esté ready
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .readyToPlay {
                    let d = item.asset.duration
                    if d.isValid && !d.isIndefinite {
                        self.state.durationSec = Float(CMTimeGetSeconds(d))
                    }
                    self.state.ready = true
                }
            }
        }

        // Polling de posición cada 0.5s
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

        // Auto-next al terminar
        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.next() }
        }

        AudioSessionManager.shared.ensureActive()
        p.play()
        state.isPlaying = true
    }

    private func teardownObservers() {
        statusObs?.invalidate(); statusObs = nil
        if let obs = timeObs { avPlayer?.removeTimeObserver(obs); timeObs = nil }
        if let obs = endObs { NotificationCenter.default.removeObserver(obs); endObs = nil }
    }
}
