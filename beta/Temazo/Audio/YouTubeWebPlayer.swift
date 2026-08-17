import Foundation
import WebKit
import UIKit
import Combine

/// Player YouTube via WKWebView + iframe YouTube Player API.
///
/// PROPÓSITO (v1.2.43):
/// Reproducción instantánea (como versión web/Android): iPhone → WKWebView →
/// iframe YouTube → CDN Google directo. Sin proxy backend, sin yt-dlp, sin
/// cookies. Segundo de latencia total.
///
/// TRADE-OFFS respecto a AVPlayer:
///  - ✅ Instant playback (Google CDN vs 5-10s del proxy yt-dlp)
///  - ✅ Sin dependencia del VPS para reproducir
///  - ❌ ~15-20% de tracks (Bad Bunny, Universal, mainstream) NO son embeddable
///       → error code 101/150 → owner debe hacer fallback a AVPlayer + yt_proxy
///  - ❌ AirPlay no funciona (iframe YouTube bloquea el picker)
///  - ❌ Offline downloads no aplican (el archivo local va por AVPlayer, aparte)
///
/// BACKGROUND AUDIO:
///  Funciona si:
///    1. AVAudioSession category = .playback + setActive(true) — lo hace AudioSessionManager
///    2. WKWebViewConfiguration.allowsInlineMediaPlayback = true
///    3. mediaTypesRequiringUserActionForPlayback = [] (autoplay legal)
///    4. WKWebView está en la view hierarchy (aunque sea 1×1 invisible)
///  Confirmado en SoundCloud/Musi y otras apps que usan iframe YT.
///
/// LOCKSCREEN CONTROLS:
///  MPNowPlayingInfoCenter + MPRemoteCommandCenter se puentean manualmente
///  desde Player.swift → aquí solo emitimos eventos vía callbacks.
///
/// USO:
///   YouTubeWebPlayer.shared.attach(to: rootUIView)  // una vez, al iniciar la app
///   YouTubeWebPlayer.shared.onError = { code in ... }
///   YouTubeWebPlayer.shared.load(videoId: "dQw4w9WgXcQ", autoplay: true)
///   YouTubeWebPlayer.shared.play() / pause() / seek(seconds:) / stop()
@MainActor
final class YouTubeWebPlayer: NSObject, ObservableObject {
    static let shared = YouTubeWebPlayer()

    // MARK: - Published state

    /// El WebView terminó de cargar el iframe API y está listo para recibir loadVideo.
    @Published var isReady = false
    /// El reproductor está reproduciendo (state YT = 1).
    @Published var isPlaying = false
    /// Buffering intermedio (state YT = 3).
    @Published var isBuffering = false
    /// Segundos actuales del stream (polleado cada 500ms desde JS).
    @Published var currentTimeSec: Double = 0
    /// Duración total en segundos (reportada por iframe cuando está lista).
    @Published var durationSec: Double = 0
    /// Último error, formato "yt_error_101" | "yt_error_150" | "yt_error_2" etc.
    @Published var lastError: String? = nil
    /// ID cargado actualmente.
    @Published var currentVideoId: String? = nil

    // MARK: - Callbacks (owner = Player.swift)

    /// Cambio de estado del YT.PlayerState:
    ///   -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued.
    var onStateChange: ((Int) -> Void)?
    /// Error del iframe YouTube:
    ///   2   = param inválido (video id malformado)
    ///   5   = HTML5 error interno
    ///   100 = video no existe / privado / borrado
    ///   101 / 150 = embed disabled por el uploader (label bloquea)
    var onError: ((Int) -> Void)?
    /// Track terminó (state → 0).
    var onEnded: (() -> Void)?
    /// Update periódico de tiempo actual (poll 500ms).
    var onCurrentTime: ((Double, Double) -> Void)?  // (currentSec, durationSec)

    // MARK: - Internal

    private var webView: WKWebView?
    private var pendingLoadId: String? = nil
    private var pendingLoadAutoplay = true

    private override init() {
        super.init()
    }

    /// Monta el WKWebView en una vista padre. Debe llamarse UNA vez al iniciar la app
    /// (típicamente desde `App.body.onAppear` o desde el `SceneDelegate`).
    /// El WebView se añade 1×1 invisible pero SÍ en la view hierarchy — requisito
    /// de iOS para que WKWebView pueda reproducir audio en background.
    func attach(to parent: UIView) {
        if webView != nil { return }  // idempotente

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(BridgeReceiver(owner: self), name: "temazoPlayer")

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.isHidden = true
        wv.isUserInteractionEnabled = false
        wv.navigationDelegate = self
        wv.scrollView.isScrollEnabled = false
        // 1×1 pero MONTADO en la jerarquía (obligatorio para audio-in-background).
        parent.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.widthAnchor.constraint(equalToConstant: 1),
            wv.heightAnchor.constraint(equalToConstant: 1),
            wv.topAnchor.constraint(equalTo: parent.topAnchor, constant: -100),
            wv.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: -100),
        ])

        self.webView = wv
        // baseURL youtube.com → permite carga del iframe_api sin CORS issues
        wv.loadHTMLString(htmlBase, baseURL: URL(string: "https://www.youtube.com"))
        print("[YTWebPlayer] attached to parent view")
    }

    /// Carga un video por ID. Si el iframe aún no está listo, queda pendiente y se
    /// dispara cuando `onReady` llegue.
    func load(videoId: String, autoplay: Bool = true) {
        currentVideoId = videoId
        lastError = nil
        isPlaying = false
        isBuffering = false
        currentTimeSec = 0
        durationSec = 0

        guard let wv = webView, isReady else {
            pendingLoadId = videoId
            pendingLoadAutoplay = autoplay
            print("[YTWebPlayer] load queued: \(videoId) (webView ready=\(isReady))")
            return
        }
        let escaped = videoId.replacingOccurrences(of: "'", with: "")
        let js = "loadVideo('\(escaped)', \(autoplay ? "true" : "false"));"
        wv.evaluateJavaScript(js) { _, err in
            if let e = err { print("[YTWebPlayer] load JS err: \(e)") }
        }
    }

    func play() {
        webView?.evaluateJavaScript("if(window.player&&player.playVideo) player.playVideo();", completionHandler: nil)
    }

    func pause() {
        webView?.evaluateJavaScript("if(window.player&&player.pauseVideo) player.pauseVideo();", completionHandler: nil)
    }

    func seek(seconds: Double) {
        let s = max(0, seconds)
        webView?.evaluateJavaScript("if(window.player&&player.seekTo) player.seekTo(\(s), true);", completionHandler: nil)
    }

    func stop() {
        webView?.evaluateJavaScript("if(window.player&&player.stopVideo) player.stopVideo();", completionHandler: nil)
        isPlaying = false
    }

    /// Volumen 0..1. iframe YouTube usa 0..100.
    func setVolume(_ v: Float) {
        let pct = max(0, min(100, Int(v * 100)))
        webView?.evaluateJavaScript("if(window.player&&player.setVolume) player.setVolume(\(pct));", completionHandler: nil)
    }

    // MARK: - JS bridge receiver (evita retain cycle sobre self)

    fileprivate func handleJSMessage(_ msg: [String: Any]) {
        let event = msg["event"] as? String ?? ""
        switch event {
        case "ready":
            isReady = true
            print("[YTWebPlayer] iframe API ready")
            // Si había un load pendiente, dispararlo ahora
            if let pending = pendingLoadId {
                let auto = pendingLoadAutoplay
                pendingLoadId = nil
                load(videoId: pending, autoplay: auto)
            }

        case "state":
            let s = msg["state"] as? Int ?? -1
            isPlaying = (s == 1)
            isBuffering = (s == 3)
            print("[YTWebPlayer] state=\(s)")
            onStateChange?(s)
            if s == 0 { onEnded?() }

        case "error":
            let code = msg["code"] as? Int ?? 0
            lastError = "yt_error_\(code)"
            print("[YTWebPlayer] error code=\(code) (101/150 = embed disabled)")
            onError?(code)

        case "time":
            let t = msg["t"] as? Double ?? 0
            let d = msg["d"] as? Double ?? 0
            currentTimeSec = t
            if d > 0.5 { durationSec = d }
            onCurrentTime?(t, d)

        default:
            break
        }
    }

    // MARK: - HTML embed (YouTube iframe Player API)

    private let htmlBase = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <style>
        html,body{margin:0;padding:0;background:#000;overflow:hidden;width:100%;height:100%}
        #player{width:100%;height:100%}
      </style>
    </head>
    <body>
      <div id="player"></div>
      <script>
        var player = null;
        var pendingId = null;
        var pendingAutoplay = true;

        function post(obj) {
          try {
            window.webkit.messageHandlers.temazoPlayer.postMessage(JSON.stringify(obj));
          } catch (e) {}
        }

        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            height: '100%',
            width: '100%',
            videoId: '',
            playerVars: {
              autoplay: 0,
              controls: 0,
              disablekb: 1,
              fs: 0,
              iv_load_policy: 3,
              modestbranding: 1,
              playsinline: 1,
              rel: 0,
              origin: 'https://www.youtube.com'
            },
            events: {
              onReady: function() {
                post({event: 'ready'});
                if (pendingId) {
                  loadVideo(pendingId, pendingAutoplay);
                  pendingId = null;
                }
              },
              onStateChange: function(e) { post({event: 'state', state: e.data}); },
              onError: function(e) { post({event: 'error', code: e.data}); }
            }
          });
        }

        function loadVideo(id, autoplay) {
          if (!player || !player.loadVideoById) {
            pendingId = id; pendingAutoplay = autoplay; return;
          }
          if (autoplay) player.loadVideoById(id);
          else player.cueVideoById(id);
        }

        // Poll cada 500ms para reportar currentTime + duration
        setInterval(function() {
          if (!player || !player.getCurrentTime) return;
          try {
            var t = player.getCurrentTime();
            var d = player.getDuration();
            post({event: 'time', t: t, d: d});
          } catch (e) {}
        }, 500);
      </script>
      <script src="https://www.youtube.com/iframe_api"></script>
    </body>
    </html>
    """
}

// MARK: - WKNavigationDelegate

extension YouTubeWebPlayer: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            print("[YTWebPlayer] navigation finished, waiting for iframe API...")
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            print("[YTWebPlayer] navigation FAIL: \(error)")
            self.lastError = "webview_navigation_fail"
        }
    }
}

// MARK: - JS bridge receiver (weak owner, evita retain cycle)

/// Wrapper que recibe mensajes desde JS y los reenvía al `YouTubeWebPlayer` sin retener.
/// (WKUserContentController retiene fuertemente el handler; usarlo directamente sobre
/// YouTubeWebPlayer.shared crearía un ciclo, aunque shared es OK. Mantengo el wrapper
/// por si en el futuro se instancian varios players independientes.)
private final class BridgeReceiver: NSObject, WKScriptMessageHandler {
    weak var owner: YouTubeWebPlayer?

    init(owner: YouTubeWebPlayer) {
        self.owner = owner
        super.init()
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                            didReceive message: WKScriptMessage) {
        guard message.name == "temazoPlayer" else { return }
        let raw: String
        if let s = message.body as? String {
            raw = s
        } else if let obj = message.body as? [String: Any],
                  let d = try? JSONSerialization.data(withJSONObject: obj),
                  let s = String(data: d, encoding: .utf8) {
            raw = s
        } else {
            return
        }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        Task { @MainActor [weak self] in
            self?.owner?.handleJSMessage(json)
        }
    }
}
