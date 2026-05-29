import Foundation
import AVFoundation
import UIKit

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
        // v2.34: ROOT CAUSE encontrado vía idevicesyslog del iPhone:
        //   audiomxd: CMSessionMgr cmsInterruptSession
        //     'Temazo(2842)' [MediaPlayback] INTERRUPTING
        //     'com.apple.WebKit(2844)' [MediaPlayback]
        //   AudioToolboxServerHandleInterruption Stop Now process
        //     'com.apple.WebKit', fade time 0.70s
        //
        // Nuestra AVAudioSession (.playback) competía con la AVAudioSession
        // que el WKWebView crea AUTOMÁTICAMENTE cuando reproduce media.
        // iOS interrumpía la del WebKit → fade 0.7s + silencio = "la pausa".
        //
        // SOLUCIÓN: NO activar AVAudioSession desde nuestra app. WebKit
        // configura + activa su propia session — igual que Safari. Sin
        // conflict. La capability "Audio" en UIBackgroundModes (Info.plist)
        // permite que la session del WebKit siga activa en background.
        do {
            let session = AVAudioSession.sharedInstance()
            // Solo setCategory para declarar la intención. NO setActive(true)
            // — eso lo hace WebKit cuando arranca el media.
            // .mixWithOthers permite que la session del Webkit coexista con
            // la nuestra sin interrupción mutua (en el raro caso que se
            // activen las dos).
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.mixWithOthers, .allowAirPlay, .allowBluetoothA2DP]
            )
            print("[AudioSession] category set (no setActive — WebKit la activa)")
        } catch {
            print("[AudioSession] setCategory error: \(error)")
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil)
        // Cuando la app va a background y hay reproducción activa, refresar
        // sesión + silent loop por si iOS los suspendió antes del lifecycle event.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func handleEnteredBackground() {
        if silentLoopActive {
            ensureActive()
            // Re-verificar que el AVAudioPlayer del silent loop sigue corriendo
            if let p = silentPlayer, !p.isPlaying { p.play() }
            print("[AudioSession] entered background — silent loop ensured")
        }
    }

    @objc private func handleWillEnterForeground() {
        if silentLoopActive {
            ensureActive()
            silentPlayer?.play()
        }
    }

    /// v2.34: NO-OP. Activar la session de la app interrumpe la del WKWebView
    /// (CMSessionMgr cmsInterruptSession). WebKit gestiona su propia session
    /// activamente cuando reproduce media. Llamadas legacy a ensureActive() se
    /// mantienen sin romper la API pero NO hacen nada.
    func ensureActive() {
        // No-op intencional. Ver comment de configure() para context completo.
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
                // Volumen 0.05 (no 0.001) — algunos iOS detectan volúmenes muy bajos
                // como "muted" y no consideran que la app produzca audio real.
                // 0.05 es imperceptible al oído pero NO muted para iOS.
                p.volume = 0.05
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
        // v2.28: iOS dispara interruption .began FALSAMENTE cuando el WKWebView en
        // UIWindow secundario empieza a producir audio (es como si iOS considerara
        // que es "otro app" interrumpiendo). Eso disparaba Player.pause() inmediato
        // → "suena 1 seg y se para" del user.
        // FIX: NO auto-pausamos en .began. .ended sigue funcionando para resumir
        // tras llamada/Siri/etc. real del sistema.
        switch type {
        case .began:
            print("[AudioSession] interruption BEGAN — IGNORADO (no auto-pause)")
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
        print("[AudioSession] routeChange reason=\(reason.rawValue)")
        // v2.28: iOS puede disparar oldDeviceUnavailable falsamente al arrancar el
        // WKWebView audio. No auto-pausamos — el user pausa si quiere.
        if reason == .oldDeviceUnavailable {
            print("[AudioSession] oldDeviceUnavailable — IGNORADO (no auto-pause)")
        }
    }
}
