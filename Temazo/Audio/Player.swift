import Foundation
import WebKit
import Combine
import UIKit

/// Player singleton. Equivalente al Player.kt del Android.
/// Usa un WKWebView que carga https://temazo.es/_app_player.html (YT iframe API).
/// La comunicación va por:
///   - app → web: `evaluateJavaScript("tmzLoad(...)")`
///   - web → app: `WKScriptMessageHandler` con nombre "AndroidBridge"
///                (el HTML del servidor llama window.AndroidBridge.onReady() etc.)
///   En iOS expondremos un objeto `AndroidBridge` polyfill que reenvía a `webkit.messageHandlers`.
@MainActor
final class Player: NSObject, ObservableObject {
    static let shared = Player()

    @Published var state = PlayerState()

    private let playerURL = URL(string: "https://temazo.es/_app_player.html")!
    private var webView: WKWebView?
    private var crossfadeMs: Int = 250
    private var pollTimer: Timer?

    // MARK: - Public API (mismo contrato que Player.kt)

    func playTrack(_ track: Track, queue: [Track], index: Int) {
        state.queue = queue
        state.index = index
        state.currentTrack = track
        // Orden importante: 1) session activa, 2) silent loop arrancado, 3) webview play
        AudioSessionManager.shared.ensureActive()
        AudioSessionManager.shared.startSilentLoop()
        ensureWebView()
        loadAndPlay(track)
        Task { try? await TemazoAPI.shared.historyAdd(track.id) }
    }

    func togglePlay() {
        if state.isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard let _ = webView else { return }
        AudioSessionManager.shared.ensureActive()
        evalJS("if(typeof tmzPlay==='function') tmzPlay();")
        state.isPlaying = true
    }

    func pause() {
        guard let _ = webView else { return }
        evalJS("if(typeof tmzPause==='function') tmzPause();")
        state.isPlaying = false
    }

    func next() {
        guard !state.queue.isEmpty else { return }
        let nextIdx = (state.index + 1) % state.queue.count
        let t = state.queue[nextIdx]
        state.index = nextIdx
        state.currentTrack = t
        loadAndPlay(t)
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func prev() {
        guard !state.queue.isEmpty else { return }
        let prevIdx = state.index <= 0 ? state.queue.count - 1 : state.index - 1
        let t = state.queue[prevIdx]
        state.index = prevIdx
        state.currentTrack = t
        loadAndPlay(t)
        Task { try? await TemazoAPI.shared.historyAdd(t.id) }
    }

    func seekTo(seconds: Float) {
        evalJS("if(typeof tmzSeek==='function') tmzSeek(\(seconds));")
        state.positionSec = seconds
    }

    func stopAll() {
        evalJS("if(typeof tmzStop==='function') tmzStop();")
        state = PlayerState()
        stopPolling()
        AudioSessionManager.shared.stopSilentLoop()
    }

    func setCrossfadeMs(_ ms: Int) {
        crossfadeMs = max(150, min(6000, ms))
    }

    // MARK: - WebView lifecycle

    func ensureWebView() {
        guard webView == nil else { return }

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.suppressesIncrementalRendering = false

        // Inyectar polyfill: el HTML llama window.AndroidBridge.onReady() etc.
        // Lo redirigimos al messageHandler nativo "TemazoBridge".
        let polyfill = """
        (function(){
          if (window.AndroidBridge) return;
          window.AndroidBridge = {
            onReady: function(){ try{ webkit.messageHandlers.TemazoBridge.postMessage({event:'onReady'}); }catch(e){} },
            onState: function(s){ try{ webkit.messageHandlers.TemazoBridge.postMessage({event:'onState', state:s}); }catch(e){} },
            onError: function(c){ try{ webkit.messageHandlers.TemazoBridge.postMessage({event:'onError', code:c}); }catch(e){} }
          };
        })();
        """
        let userScript = WKUserScript(source: polyfill,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: false)
        cfg.userContentController.addUserScript(userScript)
        cfg.userContentController.add(BridgeProxy(parent: self), name: "TemazoBridge")

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 4, height: 4), configuration: cfg)
        wv.isHidden = true
        wv.isUserInteractionEnabled = false
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TemazoApp/1.0 Mobile"
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.isScrollEnabled = false
        wv.navigationDelegate = self
        webView = wv

        // Adjuntar a una ventana visible (4×4 px) para que iOS no lo suspenda.
        attachToWindow()

        // Pre-warm: cargar la página vacía antes del primer track.
        wv.load(URLRequest(url: playerURL))
    }

    private func attachToWindow() {
        guard let wv = webView else { return }
        DispatchQueue.main.async {
            if let win = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
                if wv.superview == nil {
                    wv.translatesAutoresizingMaskIntoConstraints = true
                    wv.frame = CGRect(x: 0, y: 0, width: 4, height: 4)
                    win.addSubview(wv)
                    win.sendSubviewToBack(wv)
                }
            }
        }
    }

    private func loadAndPlay(_ track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else {
            print("[Player] track has no youtubeId, skip")
            next()
            return
        }
        ensureWebView()
        startPolling()
        // Si la página ya está cargada Y el JS está ready → loadVideoById sin recargar.
        // Si no, cargamos URL con ?v= para que la página cargue el video al inicializarse.
        if state.ready, let _ = webView {
            evalJS("""
                if(typeof fadeOutAndDo==='function'){
                    fadeOutAndDo(function(){
                        if(typeof player!=='undefined' && player.loadVideoById) player.loadVideoById('\(ytId)');
                        setTimeout(function(){ if(typeof ensurePlayingAndUnmuted==='function') ensurePlayingAndUnmuted(); }, 500);
                    }, \(crossfadeMs));
                } else if(typeof player!=='undefined' && player.loadVideoById){
                    player.loadVideoById('\(ytId)');
                }
            """)
        } else {
            let cacheBust = Int(Date().timeIntervalSince1970 / 60)
            var comps = URLComponents(url: playerURL, resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "v", value: ytId),
                URLQueryItem(name: "t", value: String(cacheBust)),
            ]
            if let url = comps.url {
                webView?.load(URLRequest(url: url))
            }
        }
        state.isPlaying = true
    }

    // MARK: - Polling 500ms

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.evalJS("(function(){ try{ return JSON.stringify({p: tmzGetTime(), d: tmzGetDuration()}); }catch(e){ return null; } })();") { result in
                guard let json = result as? String, let data = json.data(using: .utf8) else { return }
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
                   let p = obj["p"], let d = obj["d"] {
                    DispatchQueue.main.async {
                        self.state.positionSec = Float(p)
                        self.state.durationSec = Float(d)
                    }
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - JS eval

    private func evalJS(_ js: String, completion: ((Any?) -> Void)? = nil) {
        webView?.evaluateJavaScript(js) { result, _ in
            completion?(result)
        }
    }

    // MARK: - Bridge events (called from BridgeProxy on main thread)

    fileprivate func handleBridge(_ payload: [String: Any]) {
        guard let event = payload["event"] as? String else { return }
        switch event {
        case "onReady":
            state.ready = true
        case "onState":
            // YT states: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
            let s = (payload["state"] as? Int) ?? -1
            switch s {
            case 0: next()                    // ended → siguiente
            case 1: state.isPlaying = true    // playing
            // Ignoramos pause de Chromium (igual que Android)
            default: break
            }
        case "onError":
            print("[Player] YT error code=\(payload["code"] ?? "?")")
        default: break
        }
    }
}

extension Player: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Una vez la página HTML está cargada, el polyfill garantiza AndroidBridge.
            // El JS de la página llama AndroidBridge.onReady() cuando el YT iframe está listo.
        }
    }
}

private final class BridgeProxy: NSObject, WKScriptMessageHandler {
    weak var parent: Player?
    init(parent: Player) { self.parent = parent }

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        // El handler corre off-main; reenviamos al main actor.
        let body = message.body
        Task { @MainActor in
            if let dict = body as? [String: Any] {
                self.parent?.handleBridge(dict)
            }
        }
    }
}
