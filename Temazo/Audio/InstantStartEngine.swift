import Foundation
import WebKit
import UIKit
import AVFoundation

/// v2.45 — Motor de "arranque instantáneo" basado en iframe oficial de YouTube.
///
/// PROPÓSITO: tapar el gap de ~500ms-1s que tarda el AVPlayer en bootstrappear
/// (extractor + buffer). El iframe carga YouTube CDN directamente y empieza a
/// sonar en ~200ms. En cuanto el AVPlayer está `readyToPlay`, se hace handoff:
///   - iframe.pause() + mute
///   - AVPlayer.seek(iframe.currentTime) + play()
///
/// CLAVE: NO sustituye al AVPlayer. El AVPlayer sigue siendo el motor canónico
/// (background audio, lock screen, control center, etc). El iframe solo cubre
/// los primeros 1-2 segundos.
@MainActor
final class InstantStartEngine: NSObject {
    static let shared = InstantStartEngine()

    private var webView: WKWebView?
    private var hostView: UIView?
    private(set) var currentYtId: String?
    private(set) var isPlaying: Bool = false
    private var pageLoaded: Bool = false
    private var pendingPlayYtId: String?

    /// Página HTML del player iframe — la misma que usa Android.
    private static let playerURL = "https://temazo.es/_app_player.html"

    override init() {
        super.init()
    }

    /// Llamada al primer play tras instalar la app. Pre-warm de la página HTML
    /// para que el primer `startInstant` no tenga que cargarla.
    func prewarm() {
        ensureWebView()
        if !pageLoaded, let url = URL(string: Self.playerURL) {
            webView?.load(URLRequest(url: url))
        }
    }

    /// Crea el WebView una sola vez y lo monta en el window principal a 1x1 px.
    /// Necesario porque Chromium WKWebView pausa el audio si el WebView no está
    /// adjunto a una jerarquía visible.
    private func ensureWebView() {
        guard webView == nil else { return }
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsPictureInPictureMediaPlayback = false
        let ucc = WKUserContentController()
        ucc.add(self, name: "player")
        cfg.userContentController = ucc

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.allowsBackForwardNavigationGestures = false
        wv.navigationDelegate = self
        if #available(iOS 16.4, *) { wv.isInspectable = true }

        // Adjuntar al window principal — necesario para que Chromium permita audio
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            host.alpha = 0.01
            host.isUserInteractionEnabled = false
            host.addSubview(wv)
            window.addSubview(host)
            hostView = host
        }
        webView = wv
    }

    /// Arranca el iframe con la canción. ~200ms desde llamada → audio sonando.
    func startInstant(ytId: String) {
        ensureWebView()
        currentYtId = ytId
        if pageLoaded {
            let safeId = ytId.replacingOccurrences(of: "'", with: "")
            webView?.evaluateJavaScript("tmzLoad('\(safeId)')", completionHandler: nil)
            isPlaying = true
        } else {
            // Página aún cargando → guardar para reproducir al onLoad
            pendingPlayYtId = ytId
            // Forzar load con ?v=ytId si todavía no se cargó
            if let url = URL(string: "\(Self.playerURL)?v=\(ytId)") {
                webView?.load(URLRequest(url: url))
            }
        }
    }

    /// Devuelve la posición actual en segundos para que AVPlayer haga seek
    /// y haya zero-gap en el handoff.
    func currentTime(_ completion: @escaping (Double) -> Void) {
        webView?.evaluateJavaScript("tmzGetTime()") { result, _ in
            let pos = (result as? Double) ?? Double(result as? Int ?? 0)
            completion(pos)
        }
    }

    /// Pausa + silencia el iframe. Se llama tras el handoff cuando AVPlayer
    /// asume el rol de motor audible.
    func stopAfterHandoff() {
        guard isPlaying else { return }
        webView?.evaluateJavaScript("try{player.mute();player.pauseVideo();}catch(_){}", completionHandler: nil)
        isPlaying = false
    }

    /// Stop total + cleanup. Llamar cuando el user para del todo o cambia track.
    func stop() {
        webView?.evaluateJavaScript("tmzStop()", completionHandler: nil)
        isPlaying = false
        currentYtId = nil
    }
}

// MARK: - JS bridge

extension InstantStartEngine: WKScriptMessageHandler {
    nonisolated func userContentController(_ uc: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        Task { @MainActor in
            // Solo nos interesa "ready" para arrancar el pending si la página
            // cargó después de un startInstant. State changes no afectan al AVPlayer.
            if type == "ready", let pending = self.pendingPlayYtId {
                let safe = pending.replacingOccurrences(of: "'", with: "")
                self.webView?.evaluateJavaScript("tmzLoad('\(safe)')", completionHandler: nil)
                self.pendingPlayYtId = nil
                self.isPlaying = true
            }
        }
    }
}

// MARK: - Navigation delegate

extension InstantStartEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Si la carga falla, simplemente no hay instant boot. AVPlayer sigue su flow.
        print("[InstantStart] page load failed: \(error.localizedDescription)")
    }
}
