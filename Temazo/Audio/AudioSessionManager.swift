import Foundation
import AVFoundation

/// AVAudioSession para AVPlayer en background.
/// Con AVPlayer nativo (no WKWebView), background audio funciona out-of-the-box
/// si: UIBackgroundModes incluye "audio" + AVAudioSession.playback activo.
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private(set) var configured = false

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

    // No-ops: con AVPlayer nativo no necesitamos silent keep-alive
    func startSilentLoop() {}
    func stopSilentLoop() {}

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
