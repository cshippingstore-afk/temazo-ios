import Foundation

struct Track: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let slug: String?
    let artistName: String?
    let artistSlug: String?
    let artistId: Int64?
    let album: String?
    let albumId: Int64?
    let albumSlug: String?
    let cover: String?
    let coverMedium: String?
    let coverLarge: String?
    let artistImageMedium: String?
    let youtubeId: String?
    let duration: String?
    let durationSec: Int?
    let popularity: Int?
    let position: Int?
    let prevPosition: Int?
    let delta: Int?
    let isNew: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, slug
        case artistName = "artist_name"
        case artistSlug = "artist_slug"
        case artistId = "artist_id"
        case album, cover
        case albumId = "album_id"
        case albumSlug = "album_slug"
        case coverMedium = "cover_medium"
        case coverLarge = "cover_large"
        case artistImageMedium = "artist_image_medium"
        case youtubeId = "youtube_id"
        case duration
        case durationSec = "duration_sec"
        case popularity
        case position
        case prevPosition = "prev_position"
        case delta
        case isNew = "is_new"
    }

    init(id: Int64,
         title: String,
         slug: String? = nil,
         artistName: String? = nil,
         artistSlug: String? = nil,
         artistId: Int64? = nil,
         album: String? = nil,
         albumId: Int64? = nil,
         albumSlug: String? = nil,
         cover: String? = nil,
         coverMedium: String? = nil,
         coverLarge: String? = nil,
         artistImageMedium: String? = nil,
         youtubeId: String? = nil,
         duration: String? = nil,
         durationSec: Int? = nil,
         popularity: Int? = nil,
         position: Int? = nil,
         prevPosition: Int? = nil,
         delta: Int? = nil,
         isNew: Bool? = nil) {
        self.id = id
        self.title = title
        self.slug = slug
        self.artistName = artistName
        self.artistSlug = artistSlug
        self.artistId = artistId
        self.album = album
        self.albumId = albumId
        self.albumSlug = albumSlug
        self.cover = cover
        self.coverMedium = coverMedium
        self.coverLarge = coverLarge
        self.artistImageMedium = artistImageMedium
        self.youtubeId = youtubeId
        self.duration = duration
        self.durationSec = durationSec
        self.popularity = popularity
        self.position = position
        self.prevPosition = prevPosition
        self.delta = delta
        self.isNew = isNew
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id puede venir como Int o String; intenta ambos
        if let i = try? c.decode(Int64.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int64(s) {
            id = i
        } else {
            id = 0
        }
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        slug = try? c.decode(String.self, forKey: .slug)
        artistName = try? c.decode(String.self, forKey: .artistName)
        artistSlug = try? c.decode(String.self, forKey: .artistSlug)
        if let i = try? c.decode(Int64.self, forKey: .artistId) {
            artistId = i
        } else if let s = try? c.decode(String.self, forKey: .artistId), let i = Int64(s) {
            artistId = i
        } else { artistId = nil }
        album = try? c.decode(String.self, forKey: .album)
        if let i = try? c.decode(Int64.self, forKey: .albumId) {
            albumId = i
        } else if let s = try? c.decode(String.self, forKey: .albumId), let i = Int64(s) {
            albumId = i
        } else { albumId = nil }
        albumSlug = try? c.decode(String.self, forKey: .albumSlug)
        cover = try? c.decode(String.self, forKey: .cover)
        coverMedium = try? c.decode(String.self, forKey: .coverMedium)
        coverLarge = try? c.decode(String.self, forKey: .coverLarge)
        artistImageMedium = try? c.decode(String.self, forKey: .artistImageMedium)
        youtubeId = try? c.decode(String.self, forKey: .youtubeId)
        duration = try? c.decode(String.self, forKey: .duration)
        durationSec = try? c.decode(Int.self, forKey: .durationSec)
        popularity = try? c.decode(Int.self, forKey: .popularity)
        position = try? c.decode(Int.self, forKey: .position)
        prevPosition = try? c.decode(Int.self, forKey: .prevPosition)
        delta = try? c.decode(Int.self, forKey: .delta)
        if let b = try? c.decode(Bool.self, forKey: .isNew) {
            isNew = b
        } else if let i = try? c.decode(Int.self, forKey: .isNew) {
            isNew = i != 0
        } else { isNew = nil }
    }

    var coverUrl: String? {
        cover ?? coverMedium ?? coverLarge
    }

    var displayDuration: String {
        if let d = duration, !d.isEmpty { return d }
        if let s = durationSec, s > 0 {
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        return ""
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let slug: String?
    let description: String?
    let cover: String?
    let previewCover: String?
    let trackCount: Int?
    let isLikedDefault: Bool?
    let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, cover
        case previewCover = "preview_cover"
        case trackCount = "track_count"
        case isLikedDefault = "is_liked_default"
        case isPublic = "is_public"
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
        description = try? c.decode(String.self, forKey: .description)
        cover = try? c.decode(String.self, forKey: .cover)
        previewCover = try? c.decode(String.self, forKey: .previewCover)
        trackCount = try? c.decode(Int.self, forKey: .trackCount)
        if let b = try? c.decode(Bool.self, forKey: .isLikedDefault) {
            isLikedDefault = b
        } else if let i = try? c.decode(Int.self, forKey: .isLikedDefault) {
            isLikedDefault = i != 0
        } else { isLikedDefault = nil }
        if let b = try? c.decode(Bool.self, forKey: .isPublic) {
            isPublic = b
        } else if let i = try? c.decode(Int.self, forKey: .isPublic) {
            isPublic = i != 0
        } else { isPublic = nil }
    }

    /// URL absoluta de la cover (cover propio si existe, si no la del primer track),
    /// con el host de temazo.es prepended si la ruta era relativa.
    var displayCover: String? {
        let raw = cover ?? previewCover
        guard let r = raw, !r.isEmpty else { return nil }
        if r.hasPrefix("http") { return r }
        return "https://temazo.es" + (r.hasPrefix("/") ? r : "/" + r)
    }
}

struct SessionUser: Codable, Equatable {
    let id: Int
    let email: String
}
