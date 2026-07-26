import Foundation
import Combine

/// Admin API client (endpoints /api/admin/*). Reusa la cookie session de TemazoAPI.
/// `isAdmin` se refresca al login y se comprueba via /api/admin/session_check.
@MainActor
final class AdminService: ObservableObject {
    static let shared = AdminService()

    private let api = TemazoAPI.shared
    private var baseURL: URL { api.baseURL }

    @Published private(set) var isAdmin: Bool = false
    @Published private(set) var currentAdminEmail: String? = nil

    enum AdminError: LocalizedError {
        case http(Int, String)
        case decoding(String)
        case notAdmin
        case network(String)
        var errorDescription: String? {
            switch self {
            case .http(let c, let m): return "HTTP \(c): \(m)"
            case .decoding(let m):    return "Bad response: \(m)"
            case .notAdmin:           return "No admin permissions"
            case .network(let m):     return m
            }
        }
    }

    private init() {}

    // MARK: - Session status

    struct SessionCheck: Decodable {
        let ok: Bool
        let is_admin: Bool
        let user: SessionUser?
        struct SessionUser: Decodable { let id: Int; let email: String; let username: String? }
    }

    /// Refresca isAdmin desde el servidor. Llamar al login y al arrancar la app.
    func refreshAdminStatus() async {
        do {
            let sc: SessionCheck = try await getJSON("api/admin/session_check.php")
            isAdmin = sc.is_admin
            currentAdminEmail = sc.user?.email
            print("[Admin] refreshAdminStatus: is_admin=\(isAdmin) email=\(sc.user?.email ?? "-")")
        } catch {
            isAdmin = false
            currentAdminEmail = nil
            print("[Admin] refreshAdminStatus failed: \(error)")
        }
    }

    // MARK: - Tier 1

    struct ReplaceYouTubeResponse: Decodable {
        let ok: Bool
        let track_id: Int
        let youtube_id: String
        let previous: String?
    }

    @discardableResult
    func replaceYouTube(trackId: Int, youtube: String, note: String? = nil) async throws -> ReplaceYouTubeResponse {
        try await postJSON("api/admin/track_replace_youtube.php",
                           body: ["track_id": trackId, "youtube": youtube, "note": note as Any])
    }

    struct ReportResponse: Decodable {
        let ok: Bool
        let report_id: Int
    }

    /// Cualquier user logueado puede reportar (no requiere admin).
    /// reasons: no_reproduce, sounds_bad, wrong_version, bad_cover, bad_lyrics_sync,
    ///          wrong_title, wrong_artist, wrong_album, offensive, other
    @discardableResult
    func report(targetType: String, targetId: Int, reason: String, note: String? = nil) async throws -> ReportResponse {
        try await postJSON("api/admin/report.php",
                           body: ["target_type": targetType, "target_id": targetId,
                                  "reason": reason, "note": note as Any])
    }

    struct EditMetaResponse: Decodable {
        let ok: Bool
        let track_id: Int
        let updated: [String]
    }

    /// Cualquier campo nil se omite (no se modifica). Para borrar cover pasa "".
    @discardableResult
    func editMeta(trackId: Int, title: String? = nil, artistName: String? = nil,
                  releaseDate: String? = nil, coverURL: String? = nil) async throws -> EditMetaResponse {
        var body: [String: Any] = ["track_id": trackId]
        if let title { body["title"] = title }
        if let artistName { body["artist_name"] = artistName }
        if let releaseDate { body["release_date"] = releaseDate }
        if let coverURL { body["cover_url"] = coverURL }
        return try await postJSON("api/admin/track_edit_meta.php", body: body)
    }

    struct ToggleHiddenResponse: Decodable {
        let ok: Bool
        let target_type: String
        let target_id: Int
        let hidden: Int
    }

    @discardableResult
    func toggleHidden(targetType: String, targetId: Int, hidden: Bool) async throws -> ToggleHiddenResponse {
        try await postJSON("api/admin/toggle_hidden.php",
                           body: ["target_type": targetType, "target_id": targetId, "hidden": hidden])
    }

    struct ImportYouTubeResponse: Decodable {
        let ok: Bool
        let track_id: Int
        let existed: Bool
        let title: String?
        let artist: String?
        let album: String?
        let youtube_id: String?
    }

    @discardableResult
    func importYouTube(youtube: String, artistName: String? = nil,
                       albumName: String? = nil) async throws -> ImportYouTubeResponse {
        var body: [String: Any] = ["youtube": youtube]
        if let artistName { body["artist_name"] = artistName }
        if let albumName { body["album_name"] = albumName }
        return try await postJSON("api/admin/import_youtube.php", body: body)
    }

    // MARK: - Transport helpers

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await sendAndDecode(req)
    }

    private func postJSON<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // CSRF si TemazoAPI ya lo tiene (los endpoints admin actuales no lo exigen,
        // pero mandarlo es inofensivo y a futuro puede hacerse required).
        if let csrf = TemazoAPI.shared.csrfToken {
            req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        }
        // Filtrar NSNull (los `note as Any` que llegan como nil son NSNull)
        let cleaned = body.filter { !($0.value is NSNull) }
        req.httpBody = try JSONSerialization.data(withJSONObject: cleaned)
        return try await sendAndDecode(req)
    }

    private func sendAndDecode<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AdminError.network("no HTTPURLResponse")
        }
        if !(200..<300).contains(http.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 403 || http.statusCode == 401 {
                throw AdminError.notAdmin
            }
            throw AdminError.http(http.statusCode, bodyStr)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AdminError.decoding("\(error) | body: \(bodyStr.prefix(200))")
        }
    }
}
