import Foundation
import WebKit
import UIKit
import AVFoundation

/// Motor de reproducción basado en WKWebView + YouTube IFrame Player API.
/// Réplica EXACTA del Android Player.kt (que reproduce sin lag ni rate-limit):
///
///   - Android: el WebView se ata al WindowManager del sistema en una ventana
///     SYSTEM_ALERT_WINDOW 1×1 px → fuera de la jerarquía normal de la app
///     → audio sigue corriendo en background.
///
///   - iOS equivalente: el WebView vive en un UIWindow SECUNDARIO (NO en la
///     jerarquía SwiftUI normal). El UIWindow tiene tamaño 1×1 px, alpha 0.01,
///     userInteractionEnabled=false. iOS trata este UIWindow como "ventana de
///     sistema" no como "view de la app" → no aplica autoplay pause.
///
/// Por qué esto evita el throttle del proxy temazo.es/api/yt_proxy.php:
/// el iframe oficial de YouTube descarga el mp4 directamente desde googlevideo
/// usando la IP del **dispositivo del user**, no la del VPS.
@MainActor
final class WebPlayerEngine: NSObject {
    static let shared = WebPlayerEngine()

    /// La página HTML hosted en el backend que monta el YouTube IFrame Player.
    /// La misma URL que usa Android — `_app_player.html` ya soporta ambos
    /// bridges (AndroidBridge + webkit.messageHandlers.player).
    private static let playerURL = "https://temazo.es/_app_player.html"

    private(set) var webView: WKWebView!
    private var pageLoaded: Bool = false
    private var playerReady: Bool = false
    private var pollTimer: Timer?
    private var pendingPlayVideoId: String?

    /// UIWindow secundario invisible que aloja el WebView fuera de la jerarquía
    /// SwiftUI. Equivalente iOS al WindowManager de Android.
    private var hostWindow: UIWindow?

    // Callbacks que Player.swift consume
    var onReady: (() -> Void)?
    var onStateChange: ((String, Int) -> Void)?
    var onError: ((Int) -> Void)?
    var onTime: ((Float, Float) -> Void)?

    override init() {
        super.init()
        setupWebView()
        mountWebViewInSecondaryWindow()
        // Pre-warm: carga la página sin video al arrancar la app. El primer play
        // sólo necesita tmzLoad (50-100ms) en vez de full page load (1-2s).
        let url = URL(string: Self.playerURL)!
        webView.load(URLRequest(url: url))
    }

    private func setupWebView() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsPictureInPictureMediaPlayback = false
        cfg.processPool = WKProcessPool()
        let ucc = WKUserContentController()
        ucc.add(self, name: "player")
        cfg.userContentController = ucc

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
    }

    /// Crea un UIWindow secundario invisible y monta el WebView ahí.
    /// Equivalente iOS al WindowManager.addView() de Android con SYSTEM_ALERT_WINDOW.
    /// El UIWindow está fuera de la jerarquía SwiftUI → iOS NO aplica la autoplay
    /// pause policy que afecta a WebViews "huérfanos" dentro de UIWindow main.
    private func mountWebViewInSecondaryWindow() {
        // Necesitamos esperar a que haya un WindowScene activo. Si el engine se
        // instancia ANTES de que la app esté en foreground, hay que retry.
        if !attachToScene() {
            // Reintenta tras 200ms si aún no hay scene
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                _ = self.attachToScene()
            }
        }
    }

    @discardableResult
    private func attachToScene() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
        else {
            print("[WebPlayer] no foreground UIWindowScene yet, retrying...")
            return false
        }

        let window = UIWindow(windowScene: scene)
        // windowLevel alto = encima de todo, pero alpha 0.01 + 1x1 = invisible
        window.windowLevel = UIWindow.Level.alert + 1
        window.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        window.alpha = 0.01
        window.isUserInteractionEnabled = false
        window.backgroundColor = .clear
        window.isHidden = false

        let vc = UIViewController()
        vc.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false

        webView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: vc.view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
        ])

        window.rootViewController = vc
        // NO makeKeyAndVisible — el UIWindow principal de SwiftUI sigue siendo key.
        // Solo lo hacemos visible.
        self.hostWindow = window
        print("[WebPlayer] WebView mounted in secondary UIWindow (alpha 0.01, level=alert+1)")
        return true
    }

    // MARK: - Public API (consumida por Player.swift)

    func play(videoId: String) {
        pendingPlayVideoId = videoId
        let safeId = videoId.replacingOccurrences(of: "'", with: "")
        if pageLoaded && playerReady {
            webView.evaluateJavaScript("tmzLoad('\(safeId)')") { _, err in
                if let err = err { print("[WebPlayer] tmzLoad err: \(err)") }
            }
            // Retry explícito de play tras 500ms y 2000ms (red de seguridad por si
            // iOS pausa el iframe automáticamente).
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.webView.evaluateJavaScript("ensurePlayingAndUnmuted()", completionHandler: nil)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.webView.evaluateJavaScript("ensurePlayingAndUnmuted()", completionHandler: nil)
            }
        } else {
            // Si la página aún no terminó de cargar, recárgala con ?v= para arrancar
            // directamente con el video correcto. SIN cache-bust = reutiliza pre-warm.
            var comps = URLComponents(string: Self.playerURL)!
            comps.queryItems = [URLQueryItem(name: "v", value: safeId)]
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
        print("[WebPlayer] page loaded")
        // Inyectar user gesture sintético en el WebView — iOS requiere que el
        // primer audio venga de un gesture "del usuario dentro del WebView".
        let js = """
        try {
          var ev = new MouseEvent('click', {bubbles: true, cancelable: true});
          document.body.dispatchEvent(ev);
        } catch(_) {}
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebPlayer] nav failed: \(error)")
    }
}
