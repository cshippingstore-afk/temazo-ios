import Foundation
import Combine

/// ViewModel del Top de Apple Music por país hispanohablante.
/// Antes era "trending world por género"; ahora el tab Top muestra el Apple Top 100.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var lastUpdateMin: Int? = nil
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var country: String = HomeViewModel.loadStoredCountry()
    @Published var fallback: Bool = false
    @Published var totalMatched: Int = 0

    private var cache: [String: [Track]] = [:]   // key = country code
    private var cacheUpdatedAt: [String: Date] = [:]

    static let supportedCountries: [String] = [
        "ES","MX","AR","CO","CL","PE","VE","EC","BO","PY","UY","CR","PA","CU",
        "DO","PR","GT","HN","SV","NI","GQ"
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
        Task { await loadTop(force: true) }
    }

    func loadTop(force: Bool = false) async {
        if let cached = cache[country], !force {
            tracks = cached
            if let updated = cacheUpdatedAt[country] {
                let min = Int(Date().timeIntervalSince(updated) / 60)
                lastUpdateMin = min
            }
            await silentRefresh()
            return
        }
        isLoading = true
        defer { isLoading = false }
        await silentRefresh()
    }

    func forceRefresh() async {
        cache.removeValue(forKey: country)
        await silentRefresh()
    }

    private func silentRefresh() async {
        do {
            let resp = try await TemazoAPI.shared.appleTop(country: country)
            let valid = resp.tracks.filter { ($0.youtubeId ?? "").isEmpty == false }
            tracks = valid
            cache[country] = valid
            cacheUpdatedAt[country] = Date()
            fallback = resp.fallback ?? false
            totalMatched = resp.total_matched ?? valid.count
            if let updated = resp.updated_at, !updated.isEmpty {
                lastUpdateMin = HomeViewModel.minutesSinceISO(updated)
            } else {
                lastUpdateMin = 0
            }
            error = nil
            TemazoAPI.shared.prefetchYouTubeURLs(valid.prefix(20).compactMap { $0.youtubeId })
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func minutesSinceISO(_ iso: String) -> Int? {
        let fmt = ISO8601DateFormatter()
        if let d = fmt.date(from: iso) {
            return max(0, Int(Date().timeIntervalSince(d) / 60))
        }
        // Fallback: "2026-05-22 21:00:00" UTC
        let f2 = DateFormatter()
        f2.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f2.timeZone = TimeZone(identifier: "UTC")
        if let d = f2.date(from: iso) {
            return max(0, Int(Date().timeIntervalSince(d) / 60))
        }
        return nil
    }
}
