import Foundation
import WebKit
import UIKit
import AVFoundation

/// Motor de reproducción basado en WKWebView + YouTube IFrame Player API.
/// Réplica EXACTA del Android Player.kt (que reproduce sin lag ni rate-limit).
///
/// Por qué esto evita el throttle del proxy temazo.es/api/yt_proxy.php:
/// el iframe oficial de YouTube descarga el mp4 directamente desde googlevideo
/// usando la IP del **dispositivo del user**, no la del VPS. Así YouTube ve
/// millones de IPs distintas (tráfico legítimo) en lugar de UNA IP del VPS
/// haciendo miles de requests/día (que YouTube throttlea a 29 KB/s).
///
/// Para que el audio siga sonando en background:
///   - AVAudioSession .playback activa (AudioSessionManager.configure)
///   - WKWebView debe estar en la jerarquía de UIWindow (vía WebPlayerHostView).
///     Si NO está, iOS pausa el JS del WebView en background.
///   - Info.plist UIBackgroundModes incluye "audio"
///   - allowsInlineMediaPlayback = true, mediaTypesRequiringUserActionForPlayback = []
///   - Silent audio loop (AudioSessionManager.startSilentLoop) firma "estoy
///     produciendo audio" mientras el iframe sigue corriendo.
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

    // Callbacks que Player.swift consume
    var onReady: (() -> Void)?
    var onStateChange: ((String, Int) -> Void)?   // ("playing", 1) | ("ended", 0) | ...
    var onError: ((Int) -> Void)?
    var onTime: ((Float, Float) -> Void)?          // (positionSec, durationSec)

    override init() {
        super.init()
        setupWebView()
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
        // Audio del WebView va al output del AVAudioSession → background works
    }

    // MARK: - Public API (consumida por Player.swift)

    func play(videoId: String) {
        pendingPlayVideoId = videoId
        let safeId = videoId.replacingOccurrences(of: "'", with: "")
        if pageLoaded && playerReady {
            webView.evaluateJavaScript("tmzLoad('\(safeId)')") { _, err in
                if let err = err { print("[WebPlayer] tmzLoad err: \(err)") }
            }
            // Retry explícito a los 500ms — iOS suele pausar el iframe a los ~1s
            // tras el primer play por política autoplay del WebView. Llamamos
            // ensurePlayingAndUnmuted desde Swift para forzar reanudación.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.webView.evaluateJavaScript("ensurePlayingAndUnmuted()", completionHandler: nil)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.webView.evaluateJavaScript("ensurePlayingAndUnmuted()", completionHandler: nil)
            }
        } else {
            // Si la página aún no terminó de cargar, recárgala con ?v= para arrancar
            // directamente con el video correcto. SIN cache-bust (?t=) — eso forzaba
            // re-download de la página entera anulando el pre-warm = primer play lento.
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
        // El gesture de un SwiftUI Button NO cuenta. Sin esto, el iframe se
        // pausa cada ~1s aunque mediaTypesRequiringUserActionForPlayback=[].
        // El click() dispara el handler del HTML que ya tiene ensurePlayingAndUnmuted.
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
