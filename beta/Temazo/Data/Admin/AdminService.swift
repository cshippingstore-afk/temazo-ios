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

    // MARK: - Tier 2

    struct MergeResponse: Decodable {
        let ok: Bool; let source_id: Int; let target_id: Int
        let migrated: MigratedCounts
        struct MigratedCounts: Decodable { let favs: Int; let playlist_entries: Int; let plays: Int }
    }
    @discardableResult
    func mergeTracks(sourceId: Int, targetId: Int, note: String? = nil) async throws -> MergeResponse {
        var body: [String: Any] = ["source_id": sourceId, "target_id": targetId]
        if let note { body["note"] = note }
        return try await postJSON("api/admin/track_merge.php", body: body)
    }

    struct BoostResponse: Decodable {
        let ok: Bool; let track_id: Int; let popularity: Int; let previous: Int
    }
    @discardableResult
    func boostTrack(trackId: Int, popularity: Int) async throws -> BoostResponse {
        try await postJSON("api/admin/track_boost.php",
                           body: ["track_id": trackId, "popularity": popularity])
    }

    struct ReassignAlbumResponse: Decodable {
        let ok: Bool; let track_id: Int; let album_id: Int?; let album: String?
    }
    @discardableResult
    func reassignAlbum(trackId: Int, albumId: Int?) async throws -> ReassignAlbumResponse {
        try await postJSON("api/admin/track_reassign_album.php",
                           body: ["track_id": trackId, "album_id": albumId as Any])
    }

    struct GenreInfo: Decodable, Identifiable, Hashable {
        let id: Int; let name: String; let slug: String; let parent_id: Int?
    }
    struct GenresListResponse: Decodable { let ok: Bool; let genres: [GenreInfo] }
    func listGenres() async throws -> [GenreInfo] {
        let r: GenresListResponse = try await getJSON("api/admin/artist_edit_genres.php?list=1")
        return r.genres
    }

    struct EditGenresResponse: Decodable {
        let ok: Bool; let artist_id: Int; let genre_ids: [Int]; let names: [String]
    }
    @discardableResult
    func editArtistGenres(artistId: Int, genreIds: [Int]) async throws -> EditGenresResponse {
        try await postJSON("api/admin/artist_edit_genres.php",
                           body: ["artist_id": artistId, "genre_ids": genreIds])
    }

    struct EditBioResponse: Decodable { let ok: Bool; let artist_id: Int; let bio_len: Int }
    @discardableResult
    func editArtistBio(artistId: Int, bio: String) async throws -> EditBioResponse {
        try await postJSON("api/admin/artist_edit_bio.php",
                           body: ["artist_id": artistId, "bio": bio])
    }

    // MARK: - Tier 3

    struct BanResponse: Decodable {
        let ok: Bool; let artist_id: Int; let hidden: Int
        let affected: Affected
        struct Affected: Decodable { let tracks: Int; let albums: Int }
    }
    @discardableResult
    func banArtist(artistId: Int, note: String? = nil, unban: Bool = false) async throws -> BanResponse {
        var body: [String: Any] = ["artist_id": artistId]
        if let note { body["note"] = note }
        return try await sendJSON(unban ? "DELETE" : "POST",
                                  "api/admin/artist_ban.php", body: body)
    }

    struct RehydrateResponse: Decodable {
        let ok: Bool; let target_type: String; let target_id: Int
        let queued: Bool; let log_file: String
    }
    @discardableResult
    func forceRehydrate(targetType: String, targetId: Int) async throws -> RehydrateResponse {
        try await postJSON("api/admin/force_rehydrate.php",
                           body: ["target_type": targetType, "target_id": targetId])
    }

    struct ImportPlaylistResponse: Decodable {
        let ok: Bool; let task_id: String; let list_id: String
        let total_tracks: Int; let log_file: String
    }
    @discardableResult
    func importYouTubePlaylist(url: String) async throws -> ImportPlaylistResponse {
        try await postJSON("api/admin/import_playlist_youtube.php",
                           body: ["playlist_url": url])
    }

    struct AuditEntry: Decodable, Identifiable {
        let id: Int; let admin_id: Int; let admin_email: String?
        let action: String; let target_type: String; let target_id: Int?
        let before_json: String?; let after_json: String?; let note: String?
        let reverted: Int; let created_at: String
    }
    struct AuditLogResponse: Decodable { let ok: Bool; let total: Int; let entries: [AuditEntry] }
    func auditLog(limit: Int = 50, offset: Int = 0, filterAction: String? = nil) async throws -> AuditLogResponse {
        var q = "limit=\(limit)&offset=\(offset)"
        if let filterAction { q += "&action=\(filterAction)" }
        return try await getJSON("api/admin/audit_log.php?\(q)")
    }
    struct RollbackResponse: Decodable {
        let ok: Bool; let reverted: Bool; let action_id: Int; let was_action: String
    }
    @discardableResult
    func rollbackAction(actionId: Int) async throws -> RollbackResponse {
        try await postJSON("api/admin/audit_log.php", body: ["action_id": actionId])
    }

    struct YTSearchResult: Decodable, Identifiable, Hashable {
        let id: String; let title: String; let uploader: String
        let duration: Int?; let view_count: Int?; let thumbnail: String?
    }
    struct YTSearchResponse: Decodable { let ok: Bool; let query: String; let count: Int; let results: [YTSearchResult] }
    func youtubeSearch(query: String, limit: Int = 10) async throws -> [YTSearchResult] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let r: YTSearchResponse = try await getJSON("api/admin/youtube_search.php?q=\(q)&limit=\(limit)")
        return r.results
    }

    struct ReportEntry: Decodable, Identifiable {
        let id: Int; let reporter_id: Int; let reporter_email: String?
        let target_type: String; let target_id: Int; let target_name: String?
        let reason: String; let note: String?; let status: String
        let resolved_by: Int?; let resolved_at: String?; let created_at: String
    }
    struct ReportsQueueResponse: Decodable { let ok: Bool; let total: Int; let entries: [ReportEntry] }
    func reportsQueue(status: String = "open", limit: Int = 50) async throws -> ReportsQueueResponse {
        try await getJSON("api/admin/reports_queue.php?status=\(status)&limit=\(limit)")
    }
    struct ReportActionResponse: Decodable { let ok: Bool; let report_id: Int; let status: String }
    @discardableResult
    func resolveReport(reportId: Int, action: String, note: String? = nil) async throws -> ReportActionResponse {
        var body: [String: Any] = ["report_id": reportId, "action": action]
        if let note { body["note"] = note }
        return try await postJSON("api/admin/reports_queue.php", body: body)
    }

    // Helper para verbos custom (DELETE)
    private func sendJSON<T: Decodable>(_ method: String, _ path: String, body: [String: Any]) async throws -> T {
        var req = URLRequest(url: buildURL(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let csrf = TemazoAPI.shared.csrfToken {
            req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        }
        let cleaned = body.filter { !($0.value is NSNull) }
        req.httpBody = try JSONSerialization.data(withJSONObject: cleaned)
        return try await sendAndDecode(req)
    }

    // MARK: - Transport helpers

    /// Construye URL desde baseURL + path preservando query strings (no usar
    /// appendingPathComponent porque encoded '?' como %3F rompiendo la URL).
    private func buildURL(_ path: String) -> URL {
        // path viene como "api/admin/xxx.php" o "api/admin/xxx.php?a=b&c=d"
        let full = baseURL.absoluteString.hasSuffix("/")
            ? baseURL.absoluteString + path
            : baseURL.absoluteString + "/" + path
        return URL(string: full) ?? baseURL
    }

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: buildURL(path))
        req.httpMethod = "GET"
        return try await sendAndDecode(req)
    }

    private func postJSON<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var req = URLRequest(url: buildURL(path))
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
