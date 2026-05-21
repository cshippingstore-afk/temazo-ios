import Foundation
import Combine

struct GenreItem: Identifiable, Equatable {
    let id: String       // slug
    let name: String     // visible
    let emoji: String
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var selectedGenre: String = "reggaeton"
    @Published var tracks: [Track] = []
    @Published var lastUpdateMin: Int? = nil
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var country: String = HomeViewModel.loadStoredCountry()

    private var cache: [String: [Track]] = [:]   // key = "country_genre"

    static let supportedCountries: [String] = [
        "ES","MX","AR","CO","PE","VE","CL","EC","GT","CU","BO","DO",
        "HN","PY","SV","NI","CR","PA","UY","PR","GQ"
    ]

    private static func loadStoredCountry() -> String {
        let stored = UserDefaults.standard.string(forKey: "temazo_country") ?? ""
        if supportedCountries.contains(stored) { return stored }
        let locale: String = {
            if #available(iOS 16, *) {
                return Locale.current.region?.identifier ?? Locale.current.regionCode ?? ""
            } else {
                return Locale.current.regionCode ?? ""
            }
        }().uppercased()
        return supportedCountries.contains(locale) ? locale : "ES"
    }

    func setCountry(_ cc: String) {
        let safe = HomeViewModel.supportedCountries.contains(cc) ? cc : "ES"
        if country == safe { return }
        country = safe
        UserDefaults.standard.set(safe, forKey: "temazo_country")
        Task { await loadTrending(selectedGenre, force: true) }
    }

    let genres: [GenreItem] = [
        .init(id: "reggaeton", name: "Reggaetón", emoji: "🔥"),
        .init(id: "pop", name: "Pop", emoji: "🎤"),
        .init(id: "rock", name: "Rock", emoji: "🎸"),
        .init(id: "hip-hop", name: "Hip-hop", emoji: "🎧"),
        .init(id: "latin-pop", name: "Latin Pop", emoji: "🌶️"),
        .init(id: "regional-mexicano", name: "Regional Mex", emoji: "🤠"),
        .init(id: "electronic", name: "Electrónica", emoji: "💿"),
        .init(id: "rnb-soul", name: "R&B y Soul", emoji: "💜"),
        .init(id: "indie", name: "Indie", emoji: "✨"),
        .init(id: "metal", name: "Metal", emoji: "🤘"),
        .init(id: "k-pop", name: "K-Pop", emoji: "🌸"),
        .init(id: "j-pop", name: "J-Pop", emoji: "🌸"),
        .init(id: "flamenco", name: "Flamenco", emoji: "💃"),
        .init(id: "rock-latino", name: "Rock Latino", emoji: "🎸"),
        .init(id: "bachata", name: "Bachata", emoji: "🎶"),
        .init(id: "reggae-caribbean", name: "Reggae", emoji: "🏝"),
        .init(id: "folk-acoustic", name: "Folk", emoji: "🎻"),
        .init(id: "jazz", name: "Jazz", emoji: "🎷"),
        .init(id: "blues", name: "Blues", emoji: "🎺"),
        .init(id: "classical", name: "Clásica", emoji: "🎼"),
        .init(id: "country-americana", name: "Country", emoji: "🤠"),
        .init(id: "soundtracks", name: "Bandas Sonoras", emoji: "🎬"),
        .init(id: "africana", name: "Africana", emoji: "🌍"),
        .init(id: "arabe", name: "Árabe", emoji: "🪕"),
        .init(id: "bollywood-india", name: "Bollywood", emoji: "🎭"),
        .init(id: "mandopop-cantopop", name: "Mandopop", emoji: "🎴"),
    ]

    func loadTrending(_ genre: String, force: Bool = false) async {
        selectedGenre = genre
        let key = "\(country)_\(genre)"
        if let cached = cache[key], !force {
            tracks = cached
            await silentRefresh(genre)
            return
        }
        isLoading = true
        defer { isLoading = false }
        await silentRefresh(genre)
    }

    func forceRefresh() async {
        cache.removeValue(forKey: "\(country)_\(selectedGenre)")
        await silentRefresh(selectedGenre)
    }

    private func silentRefresh(_ genre: String) async {
        do {
            let resp = try await TemazoAPI.shared.trendingByGenre(genre, limit: 50, country: country)
            let valid = resp.tracks.filter { $0.youtubeId != nil && !($0.youtubeId ?? "").isEmpty }
            tracks = valid
            cache["\(country)_\(genre)"] = valid
            lastUpdateMin = resp.lastUpdateMin
            error = nil
            TemazoAPI.shared.prefetchYouTubeURLs(valid.prefix(20).compactMap { $0.youtubeId })
        } catch {
            self.error = error.localizedDescription
        }
    }
}
