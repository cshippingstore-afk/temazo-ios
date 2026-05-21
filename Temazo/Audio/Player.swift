import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer

/// Player con motor iframe oficial youtube-nocookie (vía IframePlayerEngine + WKWebView).
/// El WKWebView vive VISIBLE (160×90 px en esquina superior derecha) para que iOS
/// active PiP automático cuando la app va a background. Sin video visible, iOS no
/// activaría PiP y el audio se pararía al bloquear pantalla.
///
/// Ventajas: 100% legal frente a YouTube ToS, views cuentan, royalties al artista.
/// Trade-off: el usuario ve un mini-thumbnail del video en pantalla durante reproducción.
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private let engine = IframePlayerEngine.shared
    private var crossfadeMs: Int = 250
    private var hookedEngine = false

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        hookEngineCallbacks()
    }

    func playTrack(_ track: Track, queue: [Track], index: Int) {
        state.queue = queue
        state.index = index
        state.currentTrack = track
        state.positionSec = 0
        state.durationSec = Float(track.durationSec ?? 0)
        state.lastError = nil
        state.loadingState = .extracting
        AudioSessionManager.shared.ensureActive()
        AudioSessionManager.shared.startSilentLoop()
        startPlayback(track: track)
    }

    func togglePlay() { if state.isPlaying { pause() } else { resume() } }

    func resume() {
        AudioSessionManager.shared.ensureActive()
        AudioSessionManager.shared.startSilentLoop()
        engine.play()
        state.isPlaying = true
    }

    func pause() {
        engine.pause()
        state.isPlaying = false
        AudioSessionManager.shared.stopSilentLoop()
    }

    /// Añade un track al final de la cola actual sin interrumpir reproducción.
    func addToQueue(_ track: Track) {
        if state.queue.contains(where: { $0.id == track.id }) { return }
        state.queue.append(track)
    }

    func next() {
        guard !state.queue.isEmpty else { return }
        let nextIdx = (state.index + 1) % state.queue.count
        let t = state.queue[nextIdx]
        state.index = nextIdx
        state.currentTrack = t
        state.positionSec = 0
        state.durationSec = Float(t.durationSec ?? 0)
        state.loadingState = .extracting
        startPlayback(track: t)
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
        startPlayback(track: t)
    }

    func seekTo(seconds: Float) {
        engine.seek(seconds: Double(seconds))
        state.positionSec = seconds
    }

    func stopAll() {
        engine.pause()
        AudioSessionManager.shared.stopSilentLoop()
        state = PlayerState()
    }

    func setCrossfadeMs(_ ms: Int) { crossfadeMs = max(150, min(6000, ms)) }

    // MARK: - Internal

    private func startPlayback(track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else {
            state.lastError = "no youtubeId"; state.loadingState = .failed; return
        }
        engine.load(youtubeId: ytId)
    }

    private func hookEngineCallbacks() {
        guard !hookedEngine else { return }
        hookedEngine = true

        engine.onReady = {
            print("[Player] iframe engine ready")
        }

        engine.onStateChange = { [weak self] s in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch s {
                case .playing:
                    self.state.isPlaying = true
                    self.state.ready = true
                    self.state.loadingState = .playing
                case .paused:
                    self.state.isPlaying = false
                    self.state.loadingState = .ready
                case .buffering:
                    self.state.loadingState = .stalled
                case .ended:
                    self.next()
                case .cued:
                    self.state.loadingState = .ready
                case .unstarted, .unknown:
                    break
                }
            }
        }

        engine.onTime = { [weak self] pos, dur in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.state.positionSec = Float(pos)
                if self.state.durationSec == 0, dur > 0 {
                    self.state.durationSec = Float(dur)
                }
            }
        }

        engine.onError = { [weak self] code in
            Task { @MainActor [weak self] in
                self?.state.lastError = "YouTube error \(code)"
                self?.state.loadingState = .failed
                if code == 100 || code == 101 || code == 150 {
                    self?.next()
                }
            }
        }
    }
}
