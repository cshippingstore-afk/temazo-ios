import Foundation

// MARK: - Artist + Albums

struct Artist: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let slug: String?
    let bio: String?
    let image: String?
    let imageLarge: String?
    let followers: Int64
    let genres: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, slug, bio, image
        case imageLarge = "image_large"
        case followers, genres
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
        bio = try? c.decode(String.self, forKey: .bio)
        image = try? c.decode(String.self, forKey: .image)
        imageLarge = try? c.decode(String.self, forKey: .imageLarge)
        if let i = try? c.decode(Int64.self, forKey: .followers) { followers = i }
        else if let s = try? c.decode(String.self, forKey: .followers), let i = Int64(s) { followers = i }
        else { followers = 0 }
        genres = (try? c.decode([String].self, forKey: .genres)) ?? []
    }
}

struct AlbumSummary: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let slug: String?
    let cover: String?
    let imageMedium: String?
    let imageLarge: String?
    let releaseDate: String?
    let albumType: String?
    let totalTracks: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, cover
        case imageMedium = "image_medium"
        case imageLarge = "image_large"
        case releaseDate = "release_date"
        case albumType = "album_type"
        case totalTracks = "total_tracks"
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
        cover = try? c.decode(String.self, forKey: .cover)
        imageMedium = try? c.decode(String.self, forKey: .imageMedium)
        imageLarge = try? c.decode(String.self, forKey: .imageLarge)
        releaseDate = try? c.decode(String.self, forKey: .releaseDate)
        albumType = try? c.decode(String.self, forKey: .albumType)
        totalTracks = try? c.decode(Int.self, forKey: .totalTracks)
    }
}

struct ArtistMini: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let slug: String?
    let imageMedium: String?
    let imageLarge: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case imageMedium = "image_medium"
        case imageLarge = "image_large"
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
    }
}

struct Album: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let slug: String?
    let cover: String?
    let imageLarge: String?
    let releaseDate: String?
    let albumType: String?
    let totalTracks: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, cover
        case imageLarge = "image_large"
        case releaseDate = "release_date"
        case albumType = "album_type"
        case totalTracks = "total_tracks"
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
        cover = try? c.decode(String.self, forKey: .cover)
        imageLarge = try? c.decode(String.self, forKey: .imageLarge)
        releaseDate = try? c.decode(String.self, forKey: .releaseDate)
        albumType = try? c.decode(String.self, forKey: .albumType)
        totalTracks = try? c.decode(Int.self, forKey: .totalTracks)
    }
}

struct ArtistResponse: Decodable {
    let success: Bool
    let artist: Artist?
    let albums: [AlbumSummary]
    let topTracks: [Track]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, artist, albums, error
        case topTracks = "top_tracks"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        artist = try? c.decode(Artist.self, forKey: .artist)
        albums = (try? c.decode([AlbumSummary].self, forKey: .albums)) ?? []
        topTracks = (try? c.decode([Track].self, forKey: .topTracks)) ?? []
        error = try? c.decode(String.self, forKey: .error)
    }
}

struct AlbumResponse: Decodable {
    let success: Bool
    let album: Album?
    let artist: ArtistMini?
    let tracks: [Track]
    let error: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        album = try? c.decode(Album.self, forKey: .album)
        artist = try? c.decode(ArtistMini.self, forKey: .artist)
        tracks = (try? c.decode([Track].self, forKey: .tracks)) ?? []
        error = try? c.decode(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case success, album, artist, tracks, error
    }
}
