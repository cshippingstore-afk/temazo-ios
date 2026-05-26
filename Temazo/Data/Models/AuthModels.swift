import Foundation

// MARK: - Perfil

struct UserProfile: Codable, Equatable {
    let id: Int64
    let email: String
    let username: String?
    let avatarUrl: String?
    let birthDate: String?
    let gender: String?
    let countryCode: String?
    let createdAt: String?
    let lastLoginAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, username
        case avatarUrl = "avatar_url"
        case birthDate = "birth_date"
        case gender
        case countryCode = "country_code"
        case createdAt = "created_at"
        case lastLoginAt = "last_login_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int64.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int64(s) {
            id = i
        } else { id = 0 }
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        username = try? c.decode(String.self, forKey: .username)
        avatarUrl = try? c.decode(String.self, forKey: .avatarUrl)
        birthDate = try? c.decode(String.self, forKey: .birthDate)
        gender = try? c.decode(String.self, forKey: .gender)
        countryCode = try? c.decode(String.self, forKey: .countryCode)
        createdAt = try? c.decode(String.self, forKey: .createdAt)
        lastLoginAt = try? c.decode(String.self, forKey: .lastLoginAt)
    }

    /// URL absoluta del avatar (con host de temazo.es prepended si era relativa).
    var displayAvatarUrl: String? {
        guard let raw = avatarUrl, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") { return raw }
        return "https://temazo.es" + (raw.hasPrefix("/") ? raw : "/" + raw)
    }
}

struct ProfileCounts: Codable, Equatable {
    let favs: Int
    let playlists: Int
    let follows: Int
    let history: Int

    init(favs: Int = 0, playlists: Int = 0, follows: Int = 0, history: Int = 0) {
        self.favs = favs
        self.playlists = playlists
        self.follows = follows
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favs = (try? c.decode(Int.self, forKey: .favs)) ?? 0
        playlists = (try? c.decode(Int.self, forKey: .playlists)) ?? 0
        follows = (try? c.decode(Int.self, forKey: .follows)) ?? 0
        history = (try? c.decode(Int.self, forKey: .history)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case favs, playlists, follows, history
    }
}

struct ProfileResponse: Decodable {
    let user: UserProfile?
    let counts: ProfileCounts

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try? c.decode(UserProfile.self, forKey: .user)
        counts = (try? c.decode(ProfileCounts.self, forKey: .counts)) ?? ProfileCounts()
    }

    enum CodingKeys: String, CodingKey { case user, counts }
}

struct AvatarUploadResponse: Decodable {
    let ok: Bool
    let avatarUrl: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case avatarUrl = "avatar_url"
        case error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        avatarUrl = try? c.decode(String.self, forKey: .avatarUrl)
        error = try? c.decode(String.self, forKey: .error)
    }
}

struct UsernameResponse: Decodable {
    let ok: Bool
    let username: String?
    let error: String?
    let hint: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        username = try? c.decode(String.self, forKey: .username)
        error = try? c.decode(String.self, forKey: .error)
        hint = try? c.decode(String.self, forKey: .hint)
    }

    enum CodingKeys: String, CodingKey { case ok, username, error, hint }
}

// MARK: - Playlists CRUD

struct PlaylistCreated: Codable {
    let id: Int64
    let name: String
    let slug: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int64.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int64(s) {
            id = i
        } else { id = 0 }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        slug = try? c.decode(String.self, forKey: .slug)
    }

    enum CodingKeys: String, CodingKey { case id, name, slug }
}

struct PlaylistCreateResponse: Decodable {
    let ok: Bool
    let playlist: PlaylistCreated?
    let error: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        playlist = try? c.decode(PlaylistCreated.self, forKey: .playlist)
        error = try? c.decode(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey { case ok, playlist, error }
}

struct PlaylistAddResponse: Decodable {
    let ok: Bool
    let added: Bool
    let error: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        added = (try? c.decode(Bool.self, forKey: .added)) ?? false
        error = try? c.decode(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey { case ok, added, error }
}

// MARK: - Follow artistas

struct FollowToggleResponse: Decodable {
    let ok: Bool
    let following: Bool
    let error: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        following = (try? c.decode(Bool.self, forKey: .following)) ?? false
        error = try? c.decode(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey { case ok, following, error }
}

struct FollowedArtist: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let slug: String?
    let imageMedium: String?
    let imageLarge: String?
    let followers: Int64
    let tracksCount: Int
    let followedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case imageMedium = "image_medium"
        case imageLarge = "image_large"
        case followers
        case tracksCount = "tracks_count"
        case followedAt = "followed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int64.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int64(s) {
            id = i
        } else { id = 0 }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        slug = try? c.decode(String.self, forKey: .slug)
        imageMedium = try? c.decode(String.self, forKey: .imageMedium)
        imageLarge = try? c.decode(String.self, forKey: .imageLarge)
        if let i = try? c.decode(Int64.self, forKey: .followers) { followers = i }
        else if let s = try? c.decode(String.self, forKey: .followers), let i = Int64(s) { followers = i }
        else { followers = 0 }
        tracksCount = (try? c.decode(Int.self, forKey: .tracksCount)) ?? 0
        followedAt = try? c.decode(String.self, forKey: .followedAt)
    }

    var displayImage: String? {
        let raw = imageMedium ?? imageLarge
        guard let r = raw, !r.isEmpty else { return nil }
        if r.hasPrefix("http") { return r }
        return "https://temazo.es" + (r.hasPrefix("/") ? r : "/" + r)
    }
}

struct FollowsResponse: Decodable {
    let artists: [FollowedArtist]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artists = (try? c.decode([FollowedArtist].self, forKey: .artists)) ?? []
    }

    enum CodingKeys: String, CodingKey { case artists }
}

// MARK: - Historial

struct HistoryItem: Codable, Identifiable, Hashable {
    let id: Int64
    let playedAt: String?
    let source: String?
    let trackId: Int64
    let title: String?
    let slug: String?
    let artistId: Int64?
    let artistName: String?
    let artistSlug: String?
    let album: String?
    let coverMedium: String?
    let coverSmall: String?
    let youtubeId: String?
    let duration: String?
    let durationSec: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case playedAt = "played_at"
        case source
        case trackId = "track_id"
        case title, slug
        case artistId = "artist_id"
        case artistName = "artist_name"
        case artistSlug = "artist_slug"
        case album
        case coverMedium = "cover_medium"
        case coverSmall = "cover_small"
        case youtubeId = "youtube_id"
        case duration
        case durationSec = "duration_sec"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int64.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int64(s) {
            id = i
        } else { id = 0 }
        playedAt = try? c.decode(String.self, forKey: .playedAt)
        source = try? c.decode(String.self, forKey: .source)
        if let i = try? c.decode(Int64.self, forKey: .trackId) {
            trackId = i
        } else if let s = try? c.decode(String.self, forKey: .trackId), let i = Int64(s) {
            trackId = i
        } else { trackId = 0 }
        title = try? c.decode(String.self, forKey: .title)
        slug = try? c.decode(String.self, forKey: .slug)
        if let i = try? c.decode(Int64.self, forKey: .artistId) {
            artistId = i
        } else if let s = try? c.decode(String.self, forKey: .artistId), let i = Int64(s) {
            artistId = i
        } else { artistId = nil }
        artistName = try? c.decode(String.self, forKey: .artistName)
        artistSlug = try? c.decode(String.self, forKey: .artistSlug)
        album = try? c.decode(String.self, forKey: .album)
        coverMedium = try? c.decode(String.self, forKey: .coverMedium)
        coverSmall = try? c.decode(String.self, forKey: .coverSmall)
        youtubeId = try? c.decode(String.self, forKey: .youtubeId)
        duration = try? c.decode(String.self, forKey: .duration)
        durationSec = try? c.decode(Int.self, forKey: .durationSec)
    }

    /// Convierte a Track para reproducir desde la lista de historial.
    func toTrack() -> Track {
        // Construimos un Track via JSON intermediate porque Track tiene init from Decoder
        let dict: [String: Any] = [
            "id": trackId,
            "title": title ?? "",
            "slug": slug as Any,
            "artist_id": artistId as Any,
            "artist_name": artistName as Any,
            "artist_slug": artistSlug as Any,
            "album": album as Any,
            "cover_medium": coverMedium as Any,
            "youtube_id": youtubeId as Any,
            "duration": duration as Any,
            "duration_sec": durationSec as Any
        ].compactMapValues { v -> Any? in
            if v is NSNull { return nil }
            return v
        }
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return (try? JSONDecoder().decode(Track.self, from: data)) ?? Track.empty(id: trackId, title: title ?? "")
    }

    /// Formatea playedAt (UTC del server) a hora local del dispositivo.
    /// Hoy → "14:35", ayer → "ayer 14:35", esta semana → "Lun 14:35", más antiguo → "8 may".
    var localTimeString: String {
        guard let s = playedAt, !s.isEmpty else { return "" }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        inFmt.timeZone = TimeZone(identifier: "UTC")
        guard let date = inFmt.date(from: s) else { return s.prefix(10).description }

        let cal = Calendar.current
        let now = Date()
        let outTime = DateFormatter(); outTime.dateFormat = "HH:mm"
        let outDow = DateFormatter(); outDow.dateFormat = "EEE"
        outDow.locale = Locale(identifier: "es_ES")
        let outDate = DateFormatter(); outDate.dateFormat = "d MMM"
        outDate.locale = Locale(identifier: "es_ES")
        let timeStr = outTime.string(from: date)

        if cal.isDateInToday(date) { return timeStr }
        if cal.isDateInYesterday(date) { return "ayer \(timeStr)" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        if days >= 2 && days <= 6 {
            let dow = outDow.string(from: date).capitalized.replacingOccurrences(of: ".", with: "")
            return "\(dow) \(timeStr)"
        }
        return outDate.string(from: date)
    }
}

struct HistoryResponse: Decodable {
    let items: [HistoryItem]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([HistoryItem].self, forKey: .items)) ?? []
    }

    enum CodingKeys: String, CodingKey { case items }
}

// Helper para fallback en HistoryItem.toTrack
extension Track {
    static func empty(id: Int64, title: String) -> Track {
        // Ruta segura: pasar JSON mínimo al decoder
        let dict: [String: Any] = ["id": id, "title": title]
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return (try? JSONDecoder().decode(Track.self, from: data)) ?? {
            // Si todo falla, esto no debería ocurrir nunca, pero…
            fatalError("Track.empty failed")
        }()
    }
}

// ============================================================
// MARK: - Modelos del Top Apple Music
// ============================================================

struct AppleTopResponse: Decodable {
    let requested_cc: String?
    let country_code: String?
    let fallback: Bool?
    let updated_at: String?
    let total_matched: Int?
    let tracks: [Track]
}

struct TopTrackIdsResponse: Decodable {
    let count: Int
    let ids: [Int64]
}

// ============================================================
// MARK: - Onboarding
// ============================================================

struct OnboardingStatusResponse: Decodable {
    let onboarded: Bool
}

struct OnboardingArtist: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let slug: String?
    let image_medium: String?
    let image_large: String?
    let followers: Int64?
    let genre_slug: String?

    var displayImage: String? {
        let raw = image_medium ?? image_large ?? ""
        if raw.isEmpty { return nil }
        if raw.hasPrefix("http") { return raw }
        return "https://temazo.es" + (raw.hasPrefix("/") ? raw : "/\(raw)")
    }
}

struct OnboardingArtistsResponse: Decodable {
    let artists: [OnboardingArtist]
}

// ============================================================
// MARK: - Social: usuarios públicos
// ============================================================

struct PublicUserBrief: Decodable, Identifiable {
    let id: Int64
    let username: String?
    let avatar_url: String?
    let bio: String?
    let followers: Int?
    let following: Int?
    let public_playlists: Int?
    let followed_by_me: Int?

    var displayAvatar: String? {
        guard let raw = avatar_url, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") { return raw }
        return "https://temazo.es" + (raw.hasPrefix("/") ? raw : "/\(raw)")
    }
    var isFollowedByMe: Bool { (followed_by_me ?? 0) == 1 }
}

struct UserCounts: Decodable {
    let followers: Int
    let following: Int
    let public_playlists: Int
    let followed_artists: Int
}

struct TopItemTrack: Decodable, Identifiable {
    let id: Int64
    let title: String?
    let slug: String?
    let artist_id: Int64?
    let artist_name: String?
    let cover_medium: String?
    let plays: Int?
}

struct TopItemArtist: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let slug: String?
    let image_medium: String?
    let plays: Int?
}

struct NowPlayingItem: Decodable {
    let id: Int64
    let title: String?
    let artist_name: String?
    let cover_medium: String?
    let youtube_id: String?
    let updated_at: String?
}

struct UserPublicResponse: Decodable {
    let user: PublicUserBrief?
    let counts: UserCounts?
    let banner_url: String?
    let pinned_playlist: PublicPlaylist?
    let playlists: [PublicPlaylist]?
    let followed_artists: [FollowedArtist]?
    let top_tracks: [TopItemTrack]?
    let top_artists: [TopItemArtist]?
    let now_playing: NowPlayingItem?
    let followed_by_me: Bool?
    let blocked_by_me: Bool?
    let is_me: Bool?
}

// PublicPlaylist y DiscoverPlaylistsResponse ya están definidos en TemazoAPI.swift
// (con CodingKeys snake_case→camelCase). Aquí solo se referencian.
// FollowedArtist ya está definido más arriba en este mismo archivo.

struct UserSearchResponse: Decodable {
    let users: [PublicUserBrief]
}

struct UserListResponse: Decodable {
    let users: [PublicUserBrief]
}

struct UserFollowToggleResponse: Decodable {
    let ok: Bool?
    let following: Bool?
}

struct UserBioResponse: Decodable {
    let ok: Bool?
    let bio: String?
}

struct UserPrivacy: Decodable {
    let hide_now_playing: Int
    let hide_history: Int
    let private_session: Int
}

struct UserPrivacyResponse: Decodable {
    let privacy: UserPrivacy?
    let ok: Bool?
}

struct BlockToggleResponse: Decodable {
    let ok: Bool?
    let blocked: Bool?
}

// ============================================================
// MARK: - Notificaciones in-app
// ============================================================

struct TemazoNotification: Decodable, Identifiable {
    let id: Int64
    let kind: String
    let actor_id: Int64?
    let target_id: Int64?
    let payload: String?
    let read_at: String?
    let created_at: String?
    let actor_username: String?
    let actor_avatar: String?
    var isUnread: Bool { read_at == nil }
}

struct NotificationsResponse: Decodable {
    let notifications: [TemazoNotification]
    let unread: Int
}

struct FriendActivityEvent: Decodable, Identifiable {
    let id: Int64
    let user_id: Int64
    let kind: String
    let target_id: Int64?
    let target_kind: String?
    let payload: String?
    let created_at: String?
    let username: String?
    let avatar_url: String?
}

struct FriendActivityResponse: Decodable {
    let activity: [FriendActivityEvent]
}

// ============================================================
// MARK: - Discover/Public playlists & follow
// ============================================================

struct PublicPlaylistResponse: Decodable {
    let playlist: PublicPlaylist?
    let tracks: [Track]?
    let following: Bool?
    let is_owner: Bool?
}

struct PlaylistFollowResponse: Decodable {
    let ok: Bool?
    let following: Bool?
}

// ============================================================
// MARK: - Home por país (Inicio Spotify-style)
// ============================================================

struct HomeCountryResponse: Decodable {
    let country_code: String?
    let tracks: [Track]
    let artists: [OnboardingArtist]
}

// ============================================================
// MARK: - Monthly recap
// ============================================================

struct RecapGenre: Decodable {
    let genre: String?
    let plays: Int?
}

struct MonthlyRecapResponse: Decodable {
    let minutes: Int
    let plays: Int
    let top_tracks: [TopItemTrack]
    let top_artists: [TopItemArtist]
    let top_genres: [RecapGenre]
}

struct TracksOnlyResponse: Decodable {
    let tracks: [Track]
}

struct NowPlayingForUserResponse: Decodable {
    let now_playing: NowPlayingItem?
}

// MARK: - Events (conciertos globales)

struct EventListItem: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let slug: String?
    let primary_artist: String?
    let venue_name: String?
    let city_name: String?
    let city_slug: String?
    let country: String?
    let country_iso: String?
    let image_url: String?
    let start_date: String?
    let last_date: String?
    let dates_count: Int?
    let price: Double?
    let currency: String?
    let permalink: String?
}

struct EventsListResponse: Decodable {
    let ok: Bool?
    let country: String?
    let events: [EventListItem]?
}

// MARK: - News (noticias)

struct NewsItem: Decodable, Identifiable, Hashable {
    let id: Int64
    let source: String?
    let source_slug: String?
    let title: String
    let slug: String?
    let summary: String?
    let image: String?
    let url: String?
    let published_at: String?
}

struct NewsListResponse: Decodable {
    let ok: Bool?
    let news: [NewsItem]?
}

// ============================================================
// MARK: - Imports (solicitar artistas/canciones)
// ============================================================

struct ImportItem: Decodable, Identifiable, Hashable {
    let id: Int64
    let type: String                 // "artist" | "track"
    let artist_name: String?
    let track_title: String?
    let status: String               // pending | searching | importing | done | rejected | failed
    let request_count: Int
    let requested_at: String?
    let url: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int64.self, forKey: .id) { id = i }
        else if let s = try? c.decode(String.self, forKey: .id), let i = Int64(s) { id = i }
        else { id = 0 }
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        artist_name = try? c.decode(String.self, forKey: .artist_name)
        track_title = try? c.decode(String.self, forKey: .track_title)
        status = (try? c.decode(String.self, forKey: .status)) ?? ""
        request_count = (try? c.decode(Int.self, forKey: .request_count)) ?? 1
        requested_at = try? c.decode(String.self, forKey: .requested_at)
        url = try? c.decode(String.self, forKey: .url)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, artist_name, track_title, status, request_count, requested_at, url
    }
}

struct ImportTop: Decodable, Hashable {
    let type: String
    let artist_name: String?
    let track_title: String?
    let request_count: Int
    let status: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        artist_name = try? c.decode(String.self, forKey: .artist_name)
        track_title = try? c.decode(String.self, forKey: .track_title)
        request_count = (try? c.decode(Int.self, forKey: .request_count)) ?? 1
        status = try? c.decode(String.self, forKey: .status)
    }

    enum CodingKeys: String, CodingKey {
        case type, artist_name, track_title, request_count, status
    }
}

struct MyImportsResponse: Decodable {
    let ok: Bool?
    let mine: [ImportItem]
    let top: [ImportTop]
    let error: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? c.decode(Bool.self, forKey: .ok)
        mine = (try? c.decode([ImportItem].self, forKey: .mine)) ?? []
        top = (try? c.decode([ImportTop].self, forKey: .top)) ?? []
        error = try? c.decode(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey { case ok, mine, top, error }
}

struct ImportRequestResponse: Decodable {
    let ok: Bool?
    let status: String?              // pending | already_exists | already_requested | rate_limited
    let request_id: Int64?
    let redirect_url: String?
    let message: String?
    let error: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? c.decode(Bool.self, forKey: .ok)
        status = try? c.decode(String.self, forKey: .status)
        if let i = try? c.decode(Int64.self, forKey: .request_id) { request_id = i }
        else if let s = try? c.decode(String.self, forKey: .request_id) { request_id = Int64(s) }
        else { request_id = nil }
        redirect_url = try? c.decode(String.self, forKey: .redirect_url)
        message = try? c.decode(String.self, forKey: .message)
        error = try? c.decode(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case ok, status, request_id, redirect_url, message, error
    }
}

// ============================================================
// MARK: - Notif prefs (push notification settings)
// ============================================================

struct NotifPrefsResponse: Decodable {
    let ok: Bool?
    let prefs: [String: Bool]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? c.decode(Bool.self, forKey: .ok)
        // El backend puede devolver bools o ints (0/1). Aceptamos ambos.
        if let m = try? c.decode([String: Bool].self, forKey: .prefs) {
            prefs = m
        } else if let raw = try? c.decode([String: Int].self, forKey: .prefs) {
            prefs = raw.mapValues { $0 != 0 }
        } else {
            prefs = [:]
        }
    }

    enum CodingKeys: String, CodingKey { case ok, prefs }
}
