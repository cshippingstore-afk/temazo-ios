import Foundation
import AVFoundation

/// AVAudioSession para reproducción en background.
/// Con WKWebView (motor iframe oficial), background audio requiere mantener
/// AVAudioSession ACTIVA en todo momento — iOS pausa el JS del WebView cuando
/// la app va a background salvo que haya audio "real" sonando. Por eso usamos
/// un loop silencioso (silent.m4a) en paralelo que firma "estoy reproduciendo audio".
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private(set) var configured = false

    private var silentPlayer: AVAudioPlayer?
    private var silentLoopActive = false

    private init() {}

    func configure() {
        guard !configured else { return }
        configured = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                policy: .longFormAudio,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
            print("[AudioSession] configured \(session.category) mode=\(session.mode)")
        } catch {
            // Fallback sin policy
            do {
                let s = AVAudioSession.sharedInstance()
                try s.setCategory(.playback, mode: .default,
                                  options: [.allowAirPlay, .allowBluetoothA2DP])
                try s.setActive(true)
            } catch {
                print("[AudioSession] error: \(error)")
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil)
    }

    func ensureActive() {
        do { try AVAudioSession.sharedInstance().setActive(true, options: []) }
        catch { print("[AudioSession] ensureActive error: \(error)") }
    }

    /// Arranca un loop silencioso con AVAudioPlayer para mantener la AVAudioSession
    /// activa cuando el WKWebView pasa a background. iOS deja correr el JS del
    /// WebView mientras detecta audio "real" del proceso, así el iframe de YouTube
    /// sigue reproduciendo. Llamar al pulsar play.
    func startSilentLoop() {
        guard !silentLoopActive else { return }
        ensureActive()
        if silentPlayer == nil {
            guard let url = Bundle.main.url(forResource: "silent", withExtension: "m4a") else {
                print("[AudioSession] silent.m4a not found in bundle — background audio puede no funcionar")
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = -1     // loop infinito
                p.volume = 0.001         // imperceptible (necesita NO ser 0 para que cuente como audio)
                p.prepareToPlay()
                silentPlayer = p
            } catch {
                print("[AudioSession] silent player init err: \(error)")
                return
            }
        }
        silentPlayer?.play()
        silentLoopActive = true
        print("[AudioSession] silent loop STARTED — bg audio armed")
    }

    /// Para el silent loop al hacer pause/stop. Sin esto, la app seguiría
    /// "reproduciendo audio" (silencioso) en background indefinidamente, drenando batería.
    func stopSilentLoop() {
        guard silentLoopActive else { return }
        silentPlayer?.pause()
        silentLoopActive = false
        print("[AudioSession] silent loop STOPPED")
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        print("[AudioSession] interruption type=\(type.rawValue) info=\(info)")
        switch type {
        case .began:
            print("[AudioSession] interruption BEGAN — pausing player")
            Task { @MainActor in Player.shared.pause() }
        case .ended:
            print("[AudioSession] interruption ENDED")
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
            Task { @MainActor in Player.shared.pause() }
        }
    }
}
