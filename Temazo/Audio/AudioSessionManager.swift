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
        guard silentPlayer == nil else { return }
        guard let url = Bundle.main.url(forResource: "silent", withExtension: "m4a")
                ?? Bundle.main.url(forResource: "silent", withExtension: "wav")
                ?? Bundle.main.url(forResource: "silent", withExtension: "caf") else {
            print("[AudioSession] silent audio asset NOT FOUND in bundle — background may stop")
            return
        }

        // AVPlayer (no AVAudioPlayer): corre en proceso separado, sobrevive background mejor
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 0.001                 // casi inaudible pero >0 (iOS requiere audio real)
        player.actionAtItemEnd = .none        // no detener al final, el observer lo loopea
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false

        // Loop manual — cuando termina el item, rebobinar y seguir
        silentLooper = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        ensureActive()
        player.play()
        silentPlayer = player
        print("[AudioSession] silent loop STARTED")
    }

    func stopSilentLoop() {
        if let obs = silentLooper {
            NotificationCenter.default.removeObserver(obs)
            silentLooper = nil
        }
        silentPlayer?.pause()
        silentPlayer = nil
        print("[AudioSession] silent loop STOPPED")
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
