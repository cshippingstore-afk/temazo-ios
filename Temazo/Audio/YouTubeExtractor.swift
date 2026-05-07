import Foundation
import WebKit

/// Extrae la URL directa de stream de YouTube usando una WKWebView headless.
/// El WKWebView carga la página watch de YouTube, su JS se ejecuta normalmente
/// (incluida la deobfuscación de firmas), y luego leemos
/// `ytInitialPlayerResponse.streamingData.adaptiveFormats[*].url` con audio bitrate más alto.
///
/// Resultado: URL de stream YouTube CDN con la IP del iPhone → AVPlayer la usa directamente
/// → velocidad como Android (sin proxy de VPS en medio).
@MainActor
final class YouTubeExtractor: NSObject {
    static let shared = YouTubeExtractor()

    private var webView: WKWebView?
    private var currentContinuation: CheckedContinuation<URL, Error>?
    private var currentVideoID: String?

    // Cache de URLs extraídas (sesión-life). YouTube CDN URLs duran 4-6h
    private struct CacheEntry { let url: URL; let timestamp: Date }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 4 * 3600  // 4h

    func cachedURL(for videoID: String) -> URL? {
        guard let entry = cache[videoID] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > cacheTTL {
            cache[videoID] = nil
            return nil
        }
        return entry.url
    }

    enum ExtractorError: LocalizedError {
        case timeout, noURL, badResponse, signatureCipher
        var errorDescription: String? {
            switch self {
            case .timeout: return "extract timeout"
            case .noURL: return "URL not in response"
            case .badResponse: return "no player response"
            case .signatureCipher: return "URL needs server decipher"
            }
        }
    }

    /// Extrae la URL del stream de audio para un videoID, con la IP del iPhone.
    /// Timeout 8s. Si falla, lanza error y el caller debe usar fallback.
    func extractStreamURL(videoID: String, timeoutSec: TimeInterval = 8) async throws -> URL {
        // Cache hit → instant
        if let cached = cachedURL(for: videoID) {
            print("[YTExtractor] cache hit for \(videoID)")
            return cached
        }
        // Si ya hay extracción en curso para mismo video, espera
        if currentVideoID == videoID, let cont = currentContinuation {
            cont.resume(throwing: ExtractorError.timeout)
            currentContinuation = nil
        }
        currentVideoID = videoID

        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { cont in
                    self.currentContinuation = cont
                    self.runExtraction(videoID: videoID)
                }
            }
            group.addTask { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
                throw ExtractorError.timeout
            }
            // Devuelve la primera (URL o timeout)
            guard let result = try await group.next() else { throw ExtractorError.timeout }
            group.cancelAll()
            return result
        }
    }

    private func runExtraction(videoID: String) {
        cleanupWebView()

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.suppressesIncrementalRendering = false

        // Inyectar listener: cuando la página termine de cargar, llamamos a un script
        // que lee ytInitialPlayerResponse y devuelve la URL del audio mejor.
        let userScript = WKUserScript(source: extractorScript(),
                                      injectionTime: .atDocumentEnd,
                                      forMainFrameOnly: true)
        cfg.userContentController.addUserScript(userScript)
        cfg.userContentController.add(BridgeHandler(parent: self), name: "TemazoExtractor")

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 4, height: 4), configuration: cfg)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        wv.isHidden = true
        webView = wv

        // Carga embed page (mucho más ligera que watch). El JS de YouTube se ejecuta igual
        // y ytInitialPlayerResponse aparece poblado.
        let url = URL(string: "https://www.youtube.com/embed/\(videoID)?bpctr=9999999999&has_verified=1")!
        wv.load(URLRequest(url: url))
    }

    fileprivate func handleResult(_ result: [String: Any]) {
        if let urlStr = result["url"] as? String, let url = URL(string: urlStr) {
            // Cachear para próximos plays
            if let vid = currentVideoID {
                cache[vid] = CacheEntry(url: url, timestamp: Date())
            }
            currentContinuation?.resume(returning: url)
        } else if let err = result["error"] as? String {
            switch err {
            case "cipher":  currentContinuation?.resume(throwing: ExtractorError.signatureCipher)
            case "noresp":  currentContinuation?.resume(throwing: ExtractorError.badResponse)
            default:        currentContinuation?.resume(throwing: ExtractorError.noURL)
            }
        } else {
            currentContinuation?.resume(throwing: ExtractorError.noURL)
        }
        currentContinuation = nil
        currentVideoID = nil
        cleanupWebView()
    }

    private func cleanupWebView() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    private func extractorScript() -> String {
        return """
        (function(){
          function tryExtract() {
            try {
              var r = window.ytInitialPlayerResponse;
              if (!r || typeof r !== 'object') return null;
              var sd = r.streamingData;
              if (!sd) return {error:'noresp'};
              var formats = (sd.adaptiveFormats || []).concat(sd.formats || []);
              // Filtrar audio-only
              var audios = formats.filter(function(f){
                return f.mimeType && f.mimeType.indexOf('audio/') === 0;
              });
              if (audios.length === 0) audios = formats; // fallback
              // Elegir mejor bitrate
              audios.sort(function(a,b){ return (b.bitrate||0) - (a.bitrate||0); });
              var best = audios[0];
              if (!best) return {error:'noresp'};
              if (best.url) return {url: best.url};
              if (best.signatureCipher || best.cipher) return {error:'cipher'};
              return {error:'noresp'};
            } catch(e) {
              return {error:'exc:'+(e.message||e)};
            }
          }
          // Reintenta cada 200ms hasta 6s para esperar a que YT cargue ytInitialPlayerResponse
          var tries = 0;
          var iv = setInterval(function(){
            tries++;
            var res = tryExtract();
            if (res || tries > 30) {
              clearInterval(iv);
              try {
                webkit.messageHandlers.TemazoExtractor.postMessage(res || {error:'timeout'});
              } catch(e) {}
            }
          }, 200);
        })();
        """
    }
}

private final class BridgeHandler: NSObject, WKScriptMessageHandler {
    weak var parent: YouTubeExtractor?
    init(parent: YouTubeExtractor) { self.parent = parent }
    nonisolated func userContentController(_ ctrl: WKUserContentController, didReceive msg: WKScriptMessage) {
        let body = msg.body
        Task { @MainActor in
            if let dict = body as? [String: Any] {
                self.parent?.handleResult(dict)
            }
        }
    }
}
