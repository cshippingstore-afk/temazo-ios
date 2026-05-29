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
        // v2.36: re-análisis del log original CMSessionMgr.
        //   .mixWithOthers (v2.35) le dice a iOS "no somos el audio primario"
        //   → bloqueo de pantalla suspende todo el proceso.
        //   .playback exclusivo (v2.33) sí da background, pero v2.33 también
        //   llamaba setActive(true) en 4 sitios diferentes durante el play.
        //   CADA setActive(true) = un evento "re-claim audio focus" → iOS
        //   dispara cmsInterruptSession contra cualquier session secundaria
        //   (incluida la del WKWebView en pid distinto) → fade 0.7s.
        //
        // Fix v2.36: .playback EXCLUSIVO (background mode OK) + setActive
        // UNA SOLA VEZ al arranque, y NUNCA más. ensureActive() neutralizado.
        // WebKit creará su session DESPUÉS, sin que la nuestra se reactive
        // jamás → cero cmsInterruptSession contra WebKit.
        do {
            let session = AVAudioSession.sharedInstance()
            // v2.37: añadida policy .longFormAudio (la que usaba el v2.26 AVPlayer
            // que sí funcionaba en bloqueo). Es la declaración canónica de Apple
            // para apps de música streaming (Spotify, Apple Music): "soy audio de
            // larga duración, manténme en background al bloquear pantalla".
            // mode: .default también (no .moviePlayback) — música, no video.
            try session.setCategory(
                .playback,
                mode: .default,
                policy: .longFormAudio,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
            print("[AudioSession] active+exclusive+longFormAudio (setActive una vez)")
        } catch {
            // Fallback sin policy si el sistema no la soporta (iOS <11)
            do {
                let s = AVAudioSession.sharedInstance()
                try s.setCategory(.playback, mode: .default,
                                  options: [.allowAirPlay, .allowBluetoothA2DP])
                try s.setActive(true)
                print("[AudioSession] fallback sin policy")
            } catch {
                print("[AudioSession] configure error: \(error)")
            }
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

    /// v2.36: NO-OP definitivo. setActive solo se llama una vez en configure()
    /// al arranque de la app. Llamadas legacy no rompen pero NO re-activan
    /// → cero cmsInterruptSession contra la session del WKWebView.
    func ensureActive() {
        // Intencionalmente vacío. Ver configure() para context completo.
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
                    // Único punto donde re-activamos: después de una interrupción
                    // REAL de iOS (llamada, Siri, etc.) — iOS desactivó nuestra
                    // session, hay que re-activarla. Aquí WebKit ya estaba en
                    // pausa, así que el interrupt log no es problema.
                    do { try AVAudioSession.sharedInstance().setActive(true, options: []) }
                    catch { print("[AudioSession] reactivate err: \(error)") }
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
