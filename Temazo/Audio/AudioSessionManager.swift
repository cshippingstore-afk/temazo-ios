import Foundation
import AVFoundation

/// Configura AVAudioSession para reproducción en background.
/// Apple iOS sólo permite reproducción en background si:
///  1. UIBackgroundModes incluye "audio" (en Info.plist) ✓
///  2. AVAudioSession está en categoría .playback ACTIVA
///  3. La app está produciendo audio activamente al pasar a background
///
/// El reto con WKWebView: el audio del iframe YouTube técnicamente lo produce
/// la web; iOS a veces no detecta que es nuestra app generando audio. Para asegurar
/// background playback aplicamos un truco análogo al silent.wav del Android:
/// reproducimos un loop de audio silencioso con AVAudioPlayer mientras el usuario
/// quiere música, así iOS reconoce nuestra app como generadora de audio.
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private var silentPlayer: AVAudioPlayer?
    private(set) var configured = false

    private init() {}

    func configure() {
        guard !configured else { return }
        configured = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,
                                    mode: .default,
                                    options: [.mixWithOthers, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("[AudioSession] configure error: \(error)")
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

    // MARK: - Silent keepalive (truco background)

    func startSilentLoop() {
        guard silentPlayer == nil else { return }
        guard let url = Bundle.main.url(forResource: "silent", withExtension: "m4a")
                ?? Bundle.main.url(forResource: "silent", withExtension: "wav") else {
            print("[AudioSession] silent.m4a not found in bundle")
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.001
            p.prepareToPlay()
            p.play()
            silentPlayer = p
        } catch {
            print("[AudioSession] silent loop error: \(error)")
        }
    }

    func stopSilentLoop() {
        silentPlayer?.stop()
        silentPlayer = nil
    }

    // MARK: - Notifs

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            Player.shared.pause()
        case .ended:
            if let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
                if opts.contains(.shouldResume) {
                    Player.shared.resume()
                }
            }
        @unknown default: break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        // Si se desconectan auriculares, pausa (estándar iOS)
        guard let info = note.userInfo,
              let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        if reason == .oldDeviceUnavailable {
            Player.shared.pause()
        }
    }
}
