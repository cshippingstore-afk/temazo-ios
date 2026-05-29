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

    private var silentLoopActive = false
    // v2.38: silent loop con AVAudioEngine (genera silencio en RAM, no necesita
    // archivo en el bundle). silent.m4a nunca existió en el repo — el AVAudioPlayer
    // original SIEMPRE fallaba con "silent.m4a not found in bundle" y por eso
    // background nunca funcionó en ninguna versión WKWebView.
    private var silentEngine: AVAudioEngine?
    private var silentPlayerNode: AVAudioPlayerNode?

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
            // v2.38: re-asegurar AVAudioEngine corriendo. iOS a veces lo pausa
            // implicitamente al cambiar de foreground/background.
            if let eng = silentEngine, !eng.isRunning {
                do { try eng.start() } catch { print("[AudioSession] bg engine restart err: \(error)") }
            }
            if let n = silentPlayerNode, !n.isPlaying { n.play() }
            print("[AudioSession] entered background — silent engine ensured")
        }
    }

    @objc private func handleWillEnterForeground() {
        if silentLoopActive {
            if let eng = silentEngine, !eng.isRunning {
                do { try eng.start() } catch { print("[AudioSession] fg engine restart err: \(error)") }
            }
            silentPlayerNode?.play()
        }
    }

    /// v2.36: NO-OP definitivo. setActive solo se llama una vez en configure()
    /// al arranque de la app. Llamadas legacy no rompen pero NO re-activan
    /// → cero cmsInterruptSession contra la session del WKWebView.
    func ensureActive() {
        // Intencionalmente vacío. Ver configure() para context completo.
    }

    /// v2.38: silent loop programático con AVAudioEngine.
    /// Genera 1 segundo de silencio puro en RAM (un buffer PCM de ceros) y lo
    /// reproduce en loop infinito al 5% volumen. iOS detecta esto como audio
    /// "real" del proceso → mantiene el app + WebKit vivos en background al
    /// bloquear pantalla, igual que Spotify/Apple Music.
    /// SIN dependencia de archivos en el bundle (el viejo silent.m4a NUNCA
    /// existió → background nunca funcionaba aunque el código estuviera).
    func startSilentLoop() {
        guard !silentLoopActive else { return }
        if silentEngine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            // Formato mono 44.1kHz (canónico para audio iOS)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
                print("[AudioSession] silent engine: format init failed")
                return
            }
            // Buffer de 1 segundo (44100 frames). frameCapacity != frameLength →
            // hay que asignar frameLength explícitamente. Los frames se inicializan
            // a CERO automáticamente = silencio puro.
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else {
                print("[AudioSession] silent engine: buffer init failed")
                return
            }
            buffer.frameLength = 44100
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.volume = 0.05  // 5% — inaudible pero iOS no lo considera muted
            do {
                try engine.start()
                player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                player.play()
                silentEngine = engine
                silentPlayerNode = player
                print("[AudioSession] silent engine STARTED (programmatic silence, no asset)")
            } catch {
                print("[AudioSession] silent engine start err: \(error)")
                return
            }
        } else {
            // Reusar engine ya creado
            if let eng = silentEngine, !eng.isRunning {
                try? eng.start()
            }
            silentPlayerNode?.play()
        }
        silentLoopActive = true
    }

    /// Para el silent loop al hacer pause/stop. Sin esto, la app seguiría
    /// "reproduciendo audio" (silencioso) en background indefinidamente, drenando batería.
    func stopSilentLoop() {
        guard silentLoopActive else { return }
        silentPlayerNode?.pause()
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
