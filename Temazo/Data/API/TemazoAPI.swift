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
        // Restaura cookies guardadas de sesión anterior (mantener login)
        restoreCookies()
    }

    // MARK: - Persistencia cookies (mantener login entre lanzamientos)

    private static let cookieDefaultsKey = "temazo_session_cookies"

    /// Guarda las cookies actuales de temazo.es en UserDefaults (con expiración 1 año).
    /// Llamar tras login exitoso.
    func persistCookies() {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) else { return }
        let serializable: [[HTTPCookiePropertyKey: Any]] = cookies.compactMap { c in
            guard var props = c.properties else { return nil }
            // Forzar expiración a +1 año si no la tiene
            if props[.expires] == nil {
                props[.expires] = Date().addingTimeInterval(365 * 24 * 3600)
            }
            return props
        }
        // Convertir keys a strings para UserDefaults
        let toSave = serializable.map { dict -> [String: Any] in
            var out: [String: Any] = [:]
            for (k, v) in dict {
                if let date = v as? Date {
                    out[k.rawValue] = date.timeIntervalSince1970
                } else {
                    out[k.rawValue] = v
                }
            }
            return out
        }
        UserDefaults.standard.set(toSave, forKey: Self.cookieDefaultsKey)
        print("[Auth] persisted \(toSave.count) cookies")
    }

    private func restoreCookies() {
        guard let saved = UserDefaults.standard.array(forKey: Self.cookieDefaultsKey) as? [[String: Any]] else { return }
        var restored = 0
        for dict in saved {
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in dict {
                if k == HTTPCookiePropertyKey.expires.rawValue, let ts = v as? TimeInterval {
                    props[.expires] = Date(timeIntervalSince1970: ts)
                } else {
                    props[HTTPCookiePropertyKey(k)] = v
                }
            }
            // Si la expiración guardada ya pasó, descarta
            if let exp = props[.expires] as? Date, exp < Date() { continue }
            if let cookie = HTTPCookie(properties: props) {
                HTTPCookieStorage.shared.setCookie(cookie)
                restored += 1
            }
        }
        if restored > 0 { print("[Auth] restored \(restored) cookies from previous session") }
    }

    func clearPersistedCookies() {
        UserDefaults.standard.removeObject(forKey: Self.cookieDefaultsKey)
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

    func trendingByGenre(_ genre: String, limit: Int = 50, country: String? = nil) async throws -> TrendingResponse {
        let req = request("api/trending_world.php",
                          query: ["genre": genre, "limit": String(limit), "country": country])
        return try await send(req, TrendingResponse.self)
    }

    // MARK: - Artist + Album
    func artist(id: Int64? = nil, slug: String? = nil, name: String? = nil) async throws -> ArtistResponse {
        let req = request("api/artist.php",
                          query: ["id": id.map(String.init), "slug": slug, "name": name])
        return try await send(req, ArtistResponse.self)
    }

    func album(id: Int64? = nil, slug: String? = nil) async throws -> AlbumResponse {
        let req = request("api/album.php",
                          query: ["id": id.map(String.init), "slug": slug])
        return try await send(req, AlbumResponse.self)
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

    /// /api/auth.php?a=csrf devuelve TODO: csrf + user (null si no logged) + countries + turnstile_site_key.
    func session() async throws -> SessionResponse {
        let req = request("api/auth.php", query: ["a": "csrf"])
        let resp: CSRFResp = try await send(req, CSRFResp.self)
        if let c = resp.csrf { csrfToken = c }
        return SessionResponse(user: resp.user, csrf: resp.csrf)
    }

    func login(email: String, password: String, remember: Bool = true) async throws -> LoginResponse {
        if csrfToken == nil { _ = try await session() }
        let req = request("api/auth.php", query: ["a": "login"], method: "POST",
                          form: ["email": email, "password": password,
                                 "remember": remember ? "1" : "0"])
        let resp = try await send(req, LoginResponse.self)
        if let c = resp.csrf { csrfToken = c }
        return resp
    }

    func register(email: String, password: String, birthDate: String,
                  gender: String, countryCode: String, remember: Bool = true) async throws -> LoginResponse {
        if csrfToken == nil { _ = try await session() }
        let req = request("api/auth.php", query: ["a": "register"], method: "POST",
                          form: ["email": email, "password": password,
                                 "birth_date": birthDate, "gender": gender,
                                 "country_code": countryCode, "turnstile_token": "",
                                 "remember": remember ? "1" : "0"])
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
    func historyAdd(_ trackId: Int64, source: String = "app") async throws -> GenericResponse {
        let req = request("api/user_data.php", query: ["a": "history_add"],
                          method: "POST", form: ["track_id": String(trackId), "source": source])
        return try await send(req, GenericResponse.self)
    }

    func lyrics(_ trackId: Int64) async throws -> LyricsResponse {
        let req = request("api/lyrics_fetch.php", query: ["id": String(trackId)])
        return try await send(req, LyricsResponse.self)
    }

    // MARK: - Perfil

    func profile() async throws -> ProfileResponse {
        let req = request("api/user_data.php", query: ["a": "profile"])
        return try await send(req, ProfileResponse.self)
    }

    func avatarUpload(imageData: Data, mime: String) async throws -> AvatarUploadResponse {
        let boundary = "tmz-\(UUID().uuidString)"
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/user_data.php"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "a", value: "avatar_upload")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("temazo-app-2026", forHTTPHeaderField: "X-Temazo-Mobile")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let csrf = csrfToken { req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token") }

        var body = Data()
        let ext: String = (mime == "image/png") ? "png" : (mime == "image/webp") ? "webp" : (mime == "image/gif") ? "gif" : "jpg"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await send(req, AvatarUploadResponse.self)
    }

    @discardableResult
    func avatarDelete() async throws -> GenericResponse {
        let req = request("api/user_data.php", query: ["a": "avatar_delete"], method: "POST")
        return try await send(req, GenericResponse.self)
    }

    @discardableResult
    func usernameSet(_ username: String) async throws -> UsernameResponse {
        let req = request("api/user_data.php", query: ["a": "username_set"],
                          method: "POST", form: ["username": username])
        return try await send(req, UsernameResponse.self)
    }

    // MARK: - Playlists CRUD

    @discardableResult
    func playlistCreate(name: String, description: String = "") async throws -> PlaylistCreateResponse {
        let req = request("api/user_data.php", query: ["a": "playlist_create"],
                          method: "POST", form: ["name": name, "description": description])
        return try await send(req, PlaylistCreateResponse.self)
    }

    @discardableResult
    func playlistRename(_ playlistId: Int64, name: String, description: String = "") async throws -> GenericResponse {
        let req = request("api/user_data.php", query: ["a": "playlist_rename"],
                          method: "POST",
                          form: ["playlist_id": String(playlistId), "name": name, "description": description])
        return try await send(req, GenericResponse.self)
    }

    @discardableResult
    func playlistDelete(_ playlistId: Int64) async throws -> GenericResponse {
        let req = request("api/user_data.php", query: ["a": "playlist_delete"],
                          method: "POST", form: ["playlist_id": String(playlistId)])
        return try await send(req, GenericResponse.self)
    }

    @discardableResult
    func playlistAdd(_ playlistId: Int64, trackId: Int64) async throws -> PlaylistAddResponse {
        let req = request("api/user_data.php", query: ["a": "playlist_add"],
                          method: "POST",
                          form: ["playlist_id": String(playlistId), "track_id": String(trackId)])
        return try await send(req, PlaylistAddResponse.self)
    }

    @discardableResult
    func playlistRemove(_ playlistId: Int64, trackId: Int64) async throws -> GenericResponse {
        let req = request("api/user_data.php", query: ["a": "playlist_remove"],
                          method: "POST",
                          form: ["playlist_id": String(playlistId), "track_id": String(trackId)])
        return try await send(req, GenericResponse.self)
    }

    // MARK: - Seguir artistas

    @discardableResult
    func followToggle(artistId: Int64) async throws -> FollowToggleResponse {
        let req = request("api/user_data.php", query: ["a": "follow_toggle"],
                          method: "POST", form: ["artist_id": String(artistId)])
        return try await send(req, FollowToggleResponse.self)
    }

    func follows() async throws -> FollowsResponse {
        let req = request("api/user_data.php", query: ["a": "follows"])
        return try await send(req, FollowsResponse.self)
    }

    // MARK: - Historial

    func history(limit: Int = 50) async throws -> HistoryResponse {
        let req = request("api/user_data.php",
                          query: ["a": "history", "limit": String(limit)])
        return try await send(req, HistoryResponse.self)
    }

    /// Pre-resolve YouTube URLs en backend (cache 4h). Fire-and-forget.
    func prefetchYouTubeURLs(_ ytIds: [String]) {
        for id in ytIds where !id.isEmpty {
            let req = request("api/yt_resolve.php", query: ["id": id])
            // Best-effort: dispara la peticion y olvida
            session.dataTask(with: req) { _, _, _ in }.resume()
        }
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

struct CSRFResp: Decodable {
    let csrf: String?
    let user: SessionUser?
    let ok: Bool?
}

struct MeResp: Decodable {
    let user: SessionUser?
    let ok: Bool?
    let error: String?
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
