import Foundation
import AVFoundation
import UIKit

/// Motor de reproducción AVPlayer nativo — usado SOLO en background donde el WKWebView
/// del iframe no funciona. Carga stream extraído del backend (yt_proxy.php).
///
/// API mínima: load(ytId, fromSeconds), play, pause, seek, currentPosition, stop.
/// El estado se sincroniza desde Player con el IframePlayerEngine al pasar de
/// foreground ↔ background.
@MainActor
final class AvPlayerEngine: NSObject {
    static let shared = AvPlayerEngine()

    private static let proxyBase = "https://temazo.es/api/yt_proxy.php"

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    var onTime: ((_ position: Double) -> Void)?
    var onEnded: (() -> Void)?
    var onError: ((String) -> Void)?

    private(set) var currentYtId: String?

    /// Devuelve la posición actual del player. Si no hay reproducción, 0.
    var currentPosition: Double {
        guard let p = player, let cm = p.currentItem?.currentTime() else { return 0 }
        let t = CMTimeGetSeconds(cm)
        return t.isFinite ? max(0, t) : 0
    }

    private override init() {
        super.init()
    }

    func load(ytId: String, fromSeconds: Double, autoplay: Bool = true) {
        guard !ytId.isEmpty else { return }
        currentYtId = ytId
        var c = URLComponents(string: Self.proxyBase)
        c?.queryItems = [URLQueryItem(name: "id", value: ytId)]
        guard let url = c?.url else {
            onError?("invalid url")
            return
        }

        teardownItem()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable", "duration"])
        item.preferredForwardBufferDuration = 4.0

        if let p = player {
            p.replaceCurrentItem(with: item)
        } else {
            let p = AVPlayer(playerItem: item)
            p.automaticallyWaitsToMinimizeStalling = false
            p.allowsExternalPlayback = false
            player = p
        }

        attachObservers(for: item)

        // Seek a la posición de partida (la del iframe en el momento del switch)
        if fromSeconds > 0.5 {
            let cm = CMTime(seconds: fromSeconds, preferredTimescale: 600)
            player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if autoplay { player?.play() }
        print("[AvPlayer] load yt=\(ytId) from=\(fromSeconds)s autoplay=\(autoplay)")
    }

    func play() {
        AudioSessionManager.shared.ensureActive()
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func seek(seconds: Double) {
        let cm = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        teardownItem()
        currentYtId = nil
    }

    // MARK: - Observers

    private func attachObservers(for item: AVPlayerItem) {
        teardownObservers()

        if let p = player {
            let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
            timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cm in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.onTime?(CMTimeGetSeconds(cm))
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onEnded?()
            }
        }
    }

    private func teardownObservers() {
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        endObserver = nil
    }

    private func teardownItem() {
        teardownObservers()
    }
}
