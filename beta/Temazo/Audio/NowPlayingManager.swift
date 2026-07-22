import Foundation
import MediaPlayer
import Combine
import UIKit

/// Gestiona MPNowPlayingInfoCenter (lock screen / control center) +
/// MPRemoteCommandCenter (botones play/pause/skip de auriculares, BT, lock screen).
@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private var cancellables: Set<AnyCancellable> = []
    private var artworkCache: [String: MPMediaItemArtwork] = [:]

    private init() {
        setupRemoteCommands()
    }

    func bind(to player: Player) {
        player.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.update(with: state)
            }
            .store(in: &cancellables)
    }

    // MARK: - Remote commands

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { _ in
            Task { @MainActor in Player.shared.resume() }
            return .success
        }
        cc.pauseCommand.addTarget { _ in
            Task { @MainActor in Player.shared.pause() }
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in Player.shared.togglePlay() }
            return .success
        }
        cc.nextTrackCommand.addTarget { _ in
            Task { @MainActor in Player.shared.next() }
            return .success
        }
        cc.previousTrackCommand.addTarget { _ in
            Task { @MainActor in Player.shared.prev() }
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in Player.shared.seekTo(seconds: Float(e.positionTime)) }
            return .success
        }
        cc.stopCommand.addTarget { _ in
            Task { @MainActor in Player.shared.stopAll() }
            return .success
        }

        cc.playCommand.isEnabled = true
        cc.pauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.isEnabled = true
        cc.nextTrackCommand.isEnabled = true
        cc.previousTrackCommand.isEnabled = true
        cc.changePlaybackPositionCommand.isEnabled = true
    }

    // MARK: - Now playing info

    private func update(with state: PlayerState) {
        guard let track = state.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName ?? "",
            MPMediaItemPropertyAlbumTitle: track.album ?? "",
            MPMediaItemPropertyPlaybackDuration: Double(state.durationSec),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(state.positionSec),
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]

        if let urlStr = track.coverUrl {
            if let cached = artworkCache[urlStr] {
                info[MPMediaItemPropertyArtwork] = cached
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            } else {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                fetchArtwork(urlStr: urlStr) { [weak self] art in
                    Task { @MainActor in
                        guard let self else { return }
                        if let art {
                            self.artworkCache[urlStr] = art
                            var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                            current[MPMediaItemPropertyArtwork] = art
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                        }
                    }
                }
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    nonisolated private func fetchArtwork(urlStr: String, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        guard let url = URL(string: urlStr) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else {
                completion(nil); return
            }
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            completion(art)
        }.resume()
    }
}
