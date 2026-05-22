import Foundation
import WebKit
import UIKit
import AVFoundation

/// Motor de reproducción basado en WKWebView + YouTube IFrame API.
/// Réplica del Android Player.kt: pre-warm de la página al arrancar, JS bridge
/// para tmzLoad/tmzPlay/tmzPause/tmzSeek, polling de posición cada 500ms.
///
/// Para que el audio siga sonando en background:
///   - AVAudioSession .playback activa (gestionada por AudioSessionManager)
///   - WKWebView debe estar en la jerarquía de UIWindow (1×1 px hidden) — Apple
///     pausa media de WebViews "huérfanos".
///   - Info.plist UIBackgroundModes incluye "audio".
///   - allowsInlineMediaPlayback = true, mediaTypesRequiringUserActionForPlayback = []
///   - Silent audio loop (gestionado por AudioSessionManager) engaña al OS para
///     no matar el proceso cuando el WebView está "en pausa" desde su POV.
@MainActor
final class WebPlayerEngine: NSObject {
    static let shared = WebPlayerEngine()

    /// La página HTML hosted en el backend que carga el YouTube IFrame Player.
    private static let playerURL = "https://temazo.es/_app_player.html"

    private(set) var webView: WKWebView!
    private var pageLoaded: Bool = false
    private var playerReady: Bool = false
    private var pollTimer: Timer?
    private var pendingPlayVideoId: String?

    // Callbacks que Player.swift consume
    var onReady: (() -> Void)?
    var onStateChange: ((String, Int) -> Void)?   // ("playing", 1) | ("ended", 0) | ...
    var onError: ((Int) -> Void)?
    var onTime: ((Float, Float) -> Void)?          // (positionSec, durationSec)

    override init() {
        super.init()
        setupWebView()
        // Pre-warm: carga la página sin video al arrancar la app, así el primer
        // play sólo necesita tmzLoad (50-100ms) en vez de full page load (1-2s).
        let url = URL(string: Self.playerURL)!
        webView.load(URLRequest(url: url))
    }

    private func setupWebView() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsPictureInPictureMediaPlayback = false
        // Mantener audio en background — el processPool persistente ayuda
        cfg.processPool = WKProcessPool()
        // El user content controller recibe los mensajes desde JS (sendIOS).
        let ucc = WKUserContentController()
        ucc.add(self, name: "player")
        cfg.userContentController = ucc

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        // Audio del WebView va al output del AVAudioSession del proceso → background works
    }

    // MARK: - Public API (consumida por Player.swift)

    func play(videoId: String) {
        pendingPlayVideoId = videoId
        if pageLoaded && playerReady {
            let safeId = videoId.replacingOccurrences(of: "'", with: "")
            webView.evaluateJavaScript("tmzLoad('\(safeId)')") { _, err in
                if let err = err { print("[WebPlayer] tmzLoad err: \(err)") }
            }
        } else {
            // Si la página aún no terminó de cargar, recárgala con ?v= para arrancar
            // directamente con el video correcto.
            var comps = URLComponents(string: Self.playerURL)!
            comps.queryItems = [
                URLQueryItem(name: "v", value: videoId),
                URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
            ]
            webView.load(URLRequest(url: comps.url!))
        }
    }

    func resume() {
        webView.evaluateJavaScript("tmzPlay()", completionHandler: nil)
    }

    func pause() {
        webView.evaluateJavaScript("tmzPause()", completionHandler: nil)
    }

    func stop() {
        webView.evaluateJavaScript("tmzStop()", completionHandler: nil)
        stopPolling()
    }

    func seek(toSec sec: Float) {
        webView.evaluateJavaScript("tmzSeek(\(sec))", completionHandler: nil)
    }

    // MARK: - Polling de posición

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.pollPosition() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollPosition() {
        let js = "(function(){return [tmzGetTime(),tmzGetDuration()].join(',');})()"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            guard let s = result as? String else { return }
            let parts = s.split(separator: ",")
            guard parts.count == 2,
                  let pos = Float(parts[0]),
                  let dur = Float(parts[1]) else { return }
            self.onTime?(pos, dur)
        }
    }
}

// MARK: - WKScriptMessageHandler (mensajes desde JS)

extension WebPlayerEngine: WKScriptMessageHandler {
    nonisolated func userContentController(_ uc: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let type = body["type"] as? String ?? ""
        Task { @MainActor in
            switch type {
            case "ready":
                self.playerReady = true
                self.onReady?()
                self.startPolling()
            case "state":
                let stateName = body["state"] as? String ?? "unknown"
                let code = body["code"] as? Int ?? -1
                self.onStateChange?(stateName, code)
            case "error":
                let code = body["code"] as? Int ?? -1
                self.onError?(code)
            default:
                break
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebPlayerEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        // playerReady llegará via JS onReady → handler
        print("[WebPlayer] page loaded")
        if let pending = pendingPlayVideoId, !playerReady {
            // Si el usuario pulsó play durante el carga inicial, intenta de nuevo
            // (el JS ya habrá disparado onReady → reproducción automática).
            pendingPlayVideoId = nil
            _ = pending
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebPlayer] nav failed: \(error)")
    }
}
