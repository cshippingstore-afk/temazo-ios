import Foundation

/// API client para temazo.es. Equivalente al `TemazoApi.kt` Retrofit del Android.
/// Usa URLSession con HTTPCookieStorage compartida (auto-persistente entre lanzamientos).
final class TemazoAPI {
    static let shared = TemazoAPI()
    let baseURL = URL(string: "https://temazo.es/")!

    private let session: URLSession
    private let decoder: JSONDecoder

    /// CSRF token volátil en memoria, igual que el Android. Lo refresca session().
    var csrfToken: String? = nil

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 120
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        session = URLSession(configuration: cfg)
        decoder = JSONDecoder()
    }

    // MARK: - Helpers

    private func request(_ path: String, query: [String: String?] = [:],
                         method: String = "GET",
                         form: [String: String]? = nil) -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v -> URLQueryItem? in
            guard let v = v else { return nil }
            return URLQueryItem(name: k, value: v)
        }
        if !items.isEmpty { comps.queryItems = items }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("temazo-app-2026", forHTTPHeaderField: "X-Temazo-Mobile")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TemazoApp/1.0",
                     forHTTPHeaderField: "User-Agent")

        if method == "POST" {
            if let form = form {
                let body = form.map { "\($0.key)=\(percentEncode($0.value))" }.joined(separator: "&")
                req.httpBody = body.data(using: .utf8)
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
            if let csrf = csrfToken {
                req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
            }
        }
        return req
    }

    private func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func send<T: Decodable>(_ req: URLRequest, _ type: T.Type) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.server(http.statusCode, body)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.decoding(error.localizedDescription + " body=" + body.prefix(200))
        }
    }

    // MARK: - Endpoints

    func trendingByGenre(_ genre: String, limit: Int = 50) async throws -> TrendingResponse {
        let req = request("api/trending_world.php",
                          query: ["genre": genre, "limit": String(limit)])
        return try await send(req, TrendingResponse.self)
    }

    func artistTracks(id: Int64? = nil, name: String? = nil, exclude: String? = nil, limit: Int = 30) async throws -> ArtistTracksResponse {
        let req = request("api/artist_tracks.php",
                          query: ["id": id.map(String.init), "name": name, "exclude": exclude, "limit": String(limit)])
        return try await send(req, ArtistTracksResponse.self)
    }

    func search(_ q: String, limit: Int = 20) async throws -> SearchResponse {
        let req = request("api/search.php", query: ["q": q, "limit": String(limit)])
        return try await send(req, SearchResponse.self)
    }

    func session() async throws -> SessionResponse {
        let req = request("api/auth.php", query: ["a": "session"])
        let resp = try await send(req, SessionResponse.self)
        if let c = resp.csrf { csrfToken = c }
        return resp
    }

    func login(email: String, password: String) async throws -> LoginResponse {
        if csrfToken == nil { _ = try await session() }
        let req = request("api/auth.php", query: ["a": "login"], method: "POST",
                          form: ["email": email, "password": password])
        let resp = try await send(req, LoginResponse.self)
        if let c = resp.csrf { csrfToken = c }
        return resp
    }

    func register(email: String, password: String, birthDate: String,
                  gender: String, countryCode: String) async throws -> LoginResponse {
        if csrfToken == nil { _ = try await session() }
        let req = request("api/auth.php", query: ["a": "register"], method: "POST",
                          form: ["email": email, "password": password,
                                 "birth_date": birthDate, "gender": gender,
                                 "country_code": countryCode, "turnstile_token": ""])
        let resp = try await send(req, LoginResponse.self)
        if let c = resp.csrf { csrfToken = c }
        return resp
    }

    func logout() async throws -> LogoutResponse {
        let req = request("api/auth.php", query: ["a": "logout"], method: "POST")
        return try await send(req, LogoutResponse.self)
    }

    func favs() async throws -> FavsResponse {
        let req = request("api/user_data.php", query: ["a": "favs"])
        return try await send(req, FavsResponse.self)
    }

    func playlists() async throws -> PlaylistsResponse {
        let req = request("api/user_data.php", query: ["a": "playlists"])
        return try await send(req, PlaylistsResponse.self)
    }

    func playlistTracks(_ playlistId: Int64) async throws -> PlaylistTracksResponse {
        let req = request("api/user_data.php",
                          query: ["a": "playlist_tracks", "playlist_id": String(playlistId)])
        return try await send(req, PlaylistTracksResponse.self)
    }

    @discardableResult
    func favToggle(_ trackId: Int64) async throws -> GenericResponse {
        let req = request("api/user_data.php", query: ["a": "fav_toggle"],
                          method: "POST", form: ["track_id": String(trackId)])
        return try await send(req, GenericResponse.self)
    }

    @discardableResult
    func historyAdd(_ trackId: Int64) async throws -> GenericResponse {
        let req = request("api/user_data.php", query: ["a": "history_add"],
                          method: "POST", form: ["track_id": String(trackId)])
        return try await send(req, GenericResponse.self)
    }

    func lyrics(_ trackId: Int64) async throws -> LyricsResponse {
        let req = request("api/lyrics_fetch.php", query: ["id": String(trackId)])
        return try await send(req, LyricsResponse.self)
    }
}

// MARK: - Response models

struct TrendingResponse: Decodable {
    let success: Bool
    let genre: String?
    let tracks: [Track]
    let lastUpdateMin: Int?
    enum CodingKeys: String, CodingKey {
        case success, genre, tracks
        case lastUpdateMin = "last_update_min"
    }
}

struct ArtistTracksResponse: Decodable {
    let tracks: [Track]
}

struct SearchResponse: Decodable {
    let success: Bool?
    let query: String?
    let tracks: [Track]
}

struct SessionResponse: Decodable {
    let user: SessionUser?
    let csrf: String?
}

struct LoginResponse: Decodable {
    let ok: Bool?
    let user: SessionUser?
    let csrf: String?
    let error: String?
    let msg: String?
}

struct LogoutResponse: Decodable {
    let ok: Bool?
}

struct FavsResponse: Decodable {
    let tracks: [Track]
}

struct PlaylistsResponse: Decodable {
    let playlists: [Playlist]
}

struct PlaylistTracksResponse: Decodable {
    let tracks: [Track]
}

struct GenericResponse: Decodable {
    let ok: Bool?
    let error: String?
}

struct LyricsResponse: Decodable {
    let synced: String?
    let source: String?
    let cached: Bool?
    let error: String?
}

enum APIError: LocalizedError {
    case transport(String)
    case server(Int, String)
    case decoding(String)
    var errorDescription: String? {
        switch self {
        case .transport(let m): return "Transport: \(m)"
        case .server(let c, _): return "HTTP \(c)"
        case .decoding(let m): return "Decoding: \(m)"
        }
    }
}
