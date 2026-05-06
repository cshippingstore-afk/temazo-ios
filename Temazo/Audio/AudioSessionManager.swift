import Foundation
import AVFoundation

/// Configura AVAudioSession para reproducción en background.
///
/// Reglas clave para que WKWebView siga sonando con pantalla apagada / app minimizada:
///
///  1. Info.plist: UIBackgroundModes incluye "audio" ✓ (project.yml)
///  2. AVAudioSession categoria .playback **SIN** .mixWithOthers
///     (mixWithOthers le dice a iOS "soy secundario" → te suspende en background)
///  3. setActive(true) antes de cada play
///  4. Silent keep-alive con AVPlayer (no AVAudioPlayer) — corre en proceso separado
///     que sobrevive en background, mantiene el audio session "ocupado" mientras
///     WKWebView genera el sonido real del YouTube iframe.
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private var silentPlayer: AVPlayer?
    private var silentLooper: NSObjectProtocol?
    private(set) var configured = false

    // AVAudioEngine para producción continua de audio (más robusto que AVPlayer)
    private var engine: AVAudioEngine?
    private var engineNode: AVAudioPlayerNode?
    private var engineBuffer: AVAudioPCMBuffer?

    private init() {}

    func configure() {
        guard !configured else { return }
        configured = true

        do {
            let session = AVAudioSession.sharedInstance()
            // .playback + .moviePlayback mode = optimizado para video (YouTube iframe es video).
            // RouteSharingPolicy.longFormAudio le dice a iOS "esto es contenido largo de audio"
            // → prioriza mantenerlo vivo en background.
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                policy: .longFormAudio,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
            print("[AudioSession] configured: category=\(session.category) mode=\(session.mode) policy=longFormAudio")
        } catch {
            // Fallback: si .longFormAudio no funciona en este device, usar default
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
                try session.setActive(true, options: [])
                print("[AudioSession] fallback configured: \(session.category) mode=\(session.mode)")
            } catch {
                print("[AudioSession] configure error: \(error)")
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil)
    }

    /// Reactiva la session. Llamar JUSTO antes de cada play para asegurar que iOS
    /// vuelve a registrar la app como productora de audio.
    func ensureActive() {
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("[AudioSession] ensureActive error: \(error)")
        }
    }

    // MARK: - Silent keepalive (truco para background con WKWebView)

    func startSilentLoop() {
        ensureActive()
        startEngine()
        startSilentPlayer()
    }

    func stopSilentLoop() {
        stopSilentPlayer()
        stopEngine()
    }

    // MARK: - AVAudioEngine (producción continua de audio para evitar suspensión)

    private func startEngine() {
        guard engine == nil else { return }
        let eng = AVAudioEngine()
        let player = AVAudioPlayerNode()
        eng.attach(player)

        // Buffer de sine wave casi-silente (-50dB) que loopea sin parar
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frameCount = AVAudioFrameCount(44100)  // 1 segundo
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("[AudioEngine] no buffer"); return
        }
        buffer.frameLength = frameCount
        if let chData = buffer.floatChannelData {
            let amplitude: Float = 0.003  // ~-50dB, casi inaudible pero audio real
            for ch in 0..<Int(format.channelCount) {
                for i in 0..<Int(frameCount) {
                    chData[ch][i] = amplitude * sinf(2 * .pi * 1.0 * Float(i) / 44100.0)
                }
            }
        }

        eng.connect(player, to: eng.mainMixerNode, format: format)
        do {
            try eng.start()
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            player.play()
            engine = eng
            engineNode = player
            engineBuffer = buffer
            print("[AudioEngine] STARTED (continuous audio production)")
        } catch {
            print("[AudioEngine] start error: \(error)")
        }
    }

    private func stopEngine() {
        engineNode?.stop()
        engine?.stop()
        engine = nil
        engineNode = nil
        engineBuffer = nil
        print("[AudioEngine] STOPPED")
    }

    // MARK: - AVPlayer fallback con archivo silent.m4a (segunda capa de keep-alive)

    private func startSilentPlayer() {
        guard silentPlayer == nil else { return }
        guard let url = Bundle.main.url(forResource: "silent", withExtension: "m4a")
                ?? Bundle.main.url(forResource: "silent", withExtension: "wav") else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = 0.05  // suficiente para que iOS lo detecte
        p.actionAtItemEnd = .none
        p.allowsExternalPlayback = false
        silentLooper = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero); p?.play()
        }
        p.play()
        silentPlayer = p
        print("[AudioSession] silent AVPlayer STARTED")
    }

    private func stopSilentPlayer() {
        if let obs = silentLooper {
            NotificationCenter.default.removeObserver(obs)
            silentLooper = nil
        }
        silentPlayer?.pause()
        silentPlayer = nil
    }

    // MARK: - Interruption / route handlers

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            Task { @MainActor in Player.shared.pause() }
        case .ended:
            if let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
                if opts.contains(.shouldResume) {
                    ensureActive()
                    Task { @MainActor in Player.shared.resume() }
                }
            }
        @unknown default: break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        if reason == .oldDeviceUnavailable {
            // Auriculares desconectados → pausa (estándar iOS)
            Task { @MainActor in Player.shared.pause() }
        }
    }
}
