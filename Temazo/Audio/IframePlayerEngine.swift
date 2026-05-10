import Foundation
import WebKit
import UIKit

/// Motor de reproducción basado en WKWebView + iframe oficial de YouTube
/// (https://www.youtube-nocookie.com vía YouTube IFrame API).
///
/// Cumple ToS de YouTube (views cuentan, royalties van al artista, ads cuando los haya)
/// → app pasa review en App Store y es 100% legal.
///
/// El WKWebView vive invisible (1×1px) anclado a la keyWindow del UIApplication
/// para que el media engine de iOS lo trate como reproducción real.
@MainActor
final class IframePlayerEngine: NSObject {
    static let shared = IframePlayerEngine()

    /// Mismo HTML que consume la app Android (consistente entre plataformas).
    private static let playerURL = URL(string: "https://temazo.es/_app_player.html")!

    private var webView: WKWebView?
    private var pendingYtId: String?
    private var ready = false
    private var timePollTimer: Timer?

    /// Callbacks que el engine dispara cuando cambia su estado.
    var onReady: (() -> Void)?
    var onStateChange: ((State) -> Void)?
    var onTime: ((_ position: Double, _ duration: Double) -> Void)?
    var onError: ((Int) -> Void)?

    enum State: String { case unstarted, ended, playing, paused, buffering, cued, unknown }

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func ensureLoaded() {
        if webView != nil { return }
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        // CLAVE para background audio: PiP enabled hace que iOS NO pause el media
        // del WebView cuando la app va a background. Sin esto, el iframe se pausa
        // al bloquear pantalla aunque AVAudioSession esté activa.
        cfg.allowsPictureInPictureMediaPlayback = true
        cfg.allowsAirPlayForMediaPlayback = true
        if #available(iOS 14, *) {
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let userContent = WKUserContentController()
        userContent.add(MessageHandler(engine: self), name: "player")
        cfg.userContentController = userContent

        // Tamaño 160×90 (proporción 16:9) y VISIBLE — iOS solo activa PiP automático
        // si el video estaba visible en pantalla cuando la app va a background.
        // Lo anclamos en la esquina inferior derecha, encima del MiniPlayer.
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 160, height: 90), configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.alpha = 1.0
        wv.isUserInteractionEnabled = false
        wv.layer.cornerRadius = 6
        wv.layer.masksToBounds = true

        // Anclar a la keyWindow en una posición visible al usuario.
        // Posición: esquina superior derecha, justo bajo el TopBar.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            // Top-right corner, debajo del status bar + TopBar
            let safeTop = window.safeAreaInsets.top
            wv.frame = CGRect(
                x: window.bounds.width - 160 - 12,
                y: safeTop + 60,
                width: 160, height: 90
            )
            window.addSubview(wv)
            // Mantener encima de la UI
            window.bringSubviewToFront(wv)
        }
        webView = wv
        wv.load(URLRequest(url: Self.playerURL))
        print("[IframeEngine] webView loading \(Self.playerURL) (visible 160x90 for PiP)")
    }

    // MARK: - Comandos

    func load(youtubeId: String) {
        ensureLoaded()
        pendingYtId = youtubeId
        if ready {
            run("tmzLoad('\(escape(youtubeId))')")
        }
    }

    func play() {
        ensureLoaded()
        run("tmzPlay()")
    }

    func pause() {
        run("tmzPause()")
    }

    func seek(seconds: Double) {
        run("tmzSeek(\(seconds))")
    }

    func setVolume(_ vol: Int) {
        run("tmzSetVolume(\(max(0, min(100, vol))))")
    }

    private func run(_ js: String) {
        guard let wv = webView else { return }
        wv.evaluateJavaScript(js) { _, err in
            if let err = err {
                print("[IframeEngine] JS err: \(err)")
            }
        }
    }

    private func escape(_ s: String) -> String {
        return s.replacingOccurrences(of: "'", with: "\\'")
    }

    // MARK: - Mensajes desde el iframe

    fileprivate func handleMessage(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            onReady?()
            startTimePolling()
            if let pending = pendingYtId {
                pendingYtId = nil
                run("tmzLoad('\(escape(pending))')")
            }
        case "state":
            if let s = payload["state"] as? String {
                onStateChange?(State(rawValue: s) ?? .unknown)
            }
        case "time":
            let pos = payload["position"] as? Double ?? 0
            let dur = payload["duration"] as? Double ?? 0
            onTime?(pos, dur)
        case "error":
            let code = payload["code"] as? Int ?? -1
            onError?(code)
        default: break
        }
    }

    /// Polling de posición/duración cada 0.5s — Replicamos lo que hace Android porque
    /// el HTML actual sirve `tmzGetTime()` / `tmzGetDuration()` como API y no emite
    /// eventos `time` automáticos. Esto mantiene un solo HTML compatible con ambas plataformas.
    private func startTimePolling() {
        stopTimePolling()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let wv = self.webView else { return }
                wv.evaluateJavaScript("(function(){return [tmzGetTime(),tmzGetDuration()].join(',');})();") { res, _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        guard let s = (res as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else { return }
                        let parts = s.split(separator: ",")
                        guard parts.count == 2,
                              let pos = Double(parts[0]),
                              let dur = Double(parts[1]) else { return }
                        self.onTime?(pos, dur)
                    }
                }
            }
        }
        timePollTimer = timer
    }

    private func stopTimePolling() {
        timePollTimer?.invalidate()
        timePollTimer = nil
    }
}

/// Bridge JS ↔ Swift. Recibe mensajes que el HTML del player emite vía
/// `window.webkit.messageHandlers.player.postMessage(...)`.
private final class MessageHandler: NSObject, WKScriptMessageHandler {
    weak var engine: IframePlayerEngine?
    init(engine: IframePlayerEngine) {
        self.engine = engine
        super.init()
    }
    func userContentController(_ ucc: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard let dict = msg.body as? [String: Any] else { return }
        Task { @MainActor [weak engine] in
            engine?.handleMessage(dict)
        }
    }
}
