import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer

/// Player iOS basado en WKWebView + YouTube IFrame Player API (v2.21).
///
/// Misma arquitectura que el Android Player.kt (que reproduce sin lag):
///  - WebPlayerEngine pre-carga la página HTML al arrancar la app
///  - Las canciones se cargan con `player.loadVideoById()` JS — 50-100ms
///  - El WebView vive en una UIView 1×1 px de MainScreen (no se destruye)
///  - AVAudioSession + silent loop mantienen audio en background
///  - MediaSession via MPNowPlayingInfoCenter (lock screen + auriculares + coche)
///
/// API pública IDÉNTICA a la versión AVPlayer → el resto de la app (MiniPlayer,
/// FullPlayer, MainScreen, NowPlayingManager, etc.) no necesita cambios.
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()
    @Published var state = PlayerState()

    private let engine = WebPlayerEngine.shared
    /// Flag para evitar doble next() entre estado "ended" del player y nuestro
    /// detector manual via positionSec ≥ durationSec - 0.4s.
    private var didAutoNext: Bool = false
    private var crossfadeMs: Int = 250

    override init() {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        AudioSessionManager.shared.ensureActive()
        wireEngine()
    }

    private func wireEngine() {
        engine.onReady = { [weak self] in
            print("[Player] engine ready")
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
                // NO startSilentLoop con WKWebView — el AVAudioPlayer del silent loop
                // tomaba el output de audio del proceso y dejaba al iframe sin sonido
                // ("audio se escuchaba 1 seg y se paraba" v2.21-v2.25).
            case "paused":
                self.state.isPlaying = false
            case "buffering":
                self.state.loadingState = .extracting
            case "ended":
                if !self.didAutoNext {
                    self.didAutoNext = true
                    self.next()
                }
            case "cued":
                break
            case "unstarted":
                break
            default: break
            }
        }

        engine.onError = { [weak self] code in
            self?.state.lastError = "yt error \(code)"
            self?.state.loadingState = .failed
            // YouTube error 150 / 101 = video bloqueado en este país. Skip al siguiente.
            if code == 150 || code == 101 {
                self?.next()
            }
        }

        engine.onTime = { [weak self] pos, dur in
            guard let self else { return }
            self.state.positionSec = pos
            if dur > 0 { self.state.durationSec = dur }
            // Auto-next manual de seguridad (si el evento 'ended' no llega)
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
        // Duración del backend = source of truth; el iframe la corregirá si difiere.
        state.durationSec = Float(track.durationSec ?? 0)
        state.lastError = nil
        state.loadingState = .extracting
        didAutoNext = false
        AudioSessionManager.shared.ensureActive()
        if let ytId = track.youtubeId, !ytId.isEmpty {
            engine.play(videoId: ytId)
            state.isPlaying = true
        } else {
            state.lastError = "no youtubeId"
            state.loadingState = .failed
        }
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
        engine.resume()
        state.isPlaying = true
    }

    func pause() {
        print("[Player] pause() called")
        engine.pause()
        state.isPlaying = false
    }

    /// Añade un track al final de la cola actual sin interrumpir reproducción.
    func addToQueue(_ track: Track) {
        if state.queue.contains(where: { $0.id == track.id }) { return }
        state.queue.append(track)
    }

    func next() {
        guard !state.queue.isEmpty else { return }

        // REPEAT_ONE: recargar la misma canción
        if state.repeatMode == 2, state.index >= 0, state.index < state.queue.count {
            let t = state.queue[state.index]
            state.currentTrack = t
            state.positionSec = 0
            state.durationSec = Float(t.durationSec ?? 0)
            state.loadingState = .extracting
            didAutoNext = false
            if let ytId = t.youtubeId, !ytId.isEmpty {
                engine.play(videoId: ytId)
                state.isPlaying = true
            }
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
        if let ytId = t.youtubeId, !ytId.isEmpty {
            engine.play(videoId: ytId)
            state.isPlaying = true
        }
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
        if let ytId = t.youtubeId, !ytId.isEmpty {
            engine.play(videoId: ytId)
            state.isPlaying = true
        }
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func seekTo(seconds: Float) {
        engine.seek(toSec: seconds)
        state.positionSec = seconds
    }

    func stopAll() {
        engine.stop()
        AudioSessionManager.shared.stopSilentLoop()
        state = PlayerState()
    }

    func setCrossfadeMs(_ ms: Int) { crossfadeMs = max(150, min(6000, ms)) }
}
