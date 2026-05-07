import Foundation
import UIKit

/// Extractor super-rápido de URL de stream de YouTube.
/// Usa URLSession para fetchar la página watch + regex/JSON para extraer la URL.
/// NO usa WKWebView (mucho más rápido — ~500ms vs 3-5s).
///
/// La URL extraída tiene la IP del iPhone porque la request la hace el iPhone.
/// AVPlayer puede usar esa URL directamente desde YouTube CDN, sin proxy VPS.
@MainActor
final class YouTubeExtractor: NSObject {
    static let shared = YouTubeExtractor()

    private let session: URLSession

    private struct CacheEntry { let url: URL; let timestamp: Date }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 4 * 3600

    enum ExtractorError: LocalizedError {
        case fetchFailed(Int)
        case noPlayerResponse
        case noStreams
        case signatureCipher
        case timeout
        var errorDescription: String? {
            switch self {
            case .fetchFailed(let c): return "fetch HTTP \(c)"
            case .noPlayerResponse: return "no player response"
            case .noStreams: return "no streams"
            case .signatureCipher: return "URL needs cipher"
            case .timeout: return "timeout"
            }
        }
    }

    override init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.httpCookieAcceptPolicy = .always
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    func warmUp() { /* no-op: ya no usamos WKWebView */ }

    func cachedURL(for videoID: String) -> URL? {
        guard let e = cache[videoID] else { return nil }
        if Date().timeIntervalSince(e.timestamp) > cacheTTL { cache[videoID] = nil; return nil }
        return e.url
    }

    func extractStreamURL(videoID: String, timeoutSec: TimeInterval = 6) async throws -> URL {
        if let c = cachedURL(for: videoID) {
            print("[YTExtractor] cache hit \(videoID)")
            return c
        }
        let started = Date()
        let url = try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await self.doExtract(videoID: videoID) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
                throw ExtractorError.timeout
            }
            guard let result = try await group.next() else { throw ExtractorError.timeout }
            group.cancelAll()
            return result
        }
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "[YTExtractor] %@ extracted in %.2fs", videoID, elapsed))
        cache[videoID] = CacheEntry(url: url, timestamp: Date())
        return url
    }

    /// Pre-resuelve URLs en background (fire-and-forget).
    /// Llama esto cuando carga una lista de tracks → tap play instant para los pre-resueltos.
    func prefetch(videoIDs: [String]) {
        for id in videoIDs where cache[id] == nil {
            Task {
                _ = try? await extractStreamURL(videoID: id, timeoutSec: 8)
            }
        }
    }

    // MARK: - Private

    private func doExtract(videoID: String) async throws -> URL {
        // 1. Fetch página watch via URLSession (rápido, hereda cookies de URLSession)
        var comps = URLComponents(string: "https://www.youtube.com/watch")!
        comps.queryItems = [
            URLQueryItem(name: "v", value: videoID),
            URLQueryItem(name: "bpctr", value: "9999999999"),
            URLQueryItem(name: "has_verified", value: "1"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("es-ES,es;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ExtractorError.fetchFailed(0) }
        guard (200..<300).contains(http.statusCode) else { throw ExtractorError.fetchFailed(http.statusCode) }
        guard let html = String(data: data, encoding: .utf8) else { throw ExtractorError.noPlayerResponse }

        // 2. Extract ytInitialPlayerResponse JSON
        guard let json = extractPlayerResponseJSON(from: html) else {
            throw ExtractorError.noPlayerResponse
        }
        guard let parsed = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw ExtractorError.noPlayerResponse
        }

        // 3. Find best audio URL
        guard let streamingData = parsed["streamingData"] as? [String: Any] else {
            throw ExtractorError.noStreams
        }
        var formats: [[String: Any]] = []
        if let af = streamingData["adaptiveFormats"] as? [[String: Any]] { formats.append(contentsOf: af) }
        if let f = streamingData["formats"] as? [[String: Any]] { formats.append(contentsOf: f) }
        if formats.isEmpty { throw ExtractorError.noStreams }

        // Audio-only primero
        var audios = formats.filter {
            ($0["mimeType"] as? String)?.hasPrefix("audio/") ?? false
        }
        if audios.isEmpty { audios = formats }  // fallback
        audios.sort {
            ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0)
        }

        for f in audios {
            if let urlStr = f["url"] as? String, let url = URL(string: urlStr) {
                return url
            }
            // Si tiene signatureCipher → no implementado, probar el siguiente
        }
        throw ExtractorError.signatureCipher
    }

    /// Encuentra `ytInitialPlayerResponse = {...};` y devuelve los bytes del JSON.
    /// Hace balance de llaves manualmente porque regex puro falla con JSON anidado.
    private func extractPlayerResponseJSON(from html: String) -> Data? {
        let needle = "ytInitialPlayerResponse"
        guard let needleRange = html.range(of: needle) else { return nil }
        // Buscar primera "{" tras needle
        guard let braceStart = html[needleRange.upperBound...].firstIndex(of: "{") else { return nil }
        // Balance de llaves desde ahí
        var depth = 0
        var inString = false
        var escape = false
        var idx = braceStart
        let end = html.endIndex
        while idx < end {
            let c = html[idx]
            if escape { escape = false }
            else if c == "\\" { escape = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        let jsonStr = String(html[braceStart...idx])
                        return jsonStr.data(using: .utf8)
                    }
                }
            }
            idx = html.index(after: idx)
        }
        return nil
    }
}
