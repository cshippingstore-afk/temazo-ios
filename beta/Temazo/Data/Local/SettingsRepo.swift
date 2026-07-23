import Foundation
import Combine

/// Settings repo (UserDefaults). Equivalente de SettingsRepo.kt.
@MainActor
final class SettingsRepo: ObservableObject {
    static let shared = SettingsRepo()
    private let kCrossfadeOn = "crossfade_enabled"
    private let kCrossfadeSec = "crossfade_seconds"
    // BETA v1.2: preferencias offline (Spotify-style)
    private let kAutoDownloadFavs = "auto_download_favorites"
    private let kAutoDownloadMyPls = "auto_download_my_playlists"
    private let kAutoDownloadFollowedPls = "auto_download_followed_playlists"
    private let kOfflineMode = "offline_mode_only"

    @Published var crossfadeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(crossfadeEnabled, forKey: kCrossfadeOn)
            applyToPlayer()
        }
    }
    @Published var crossfadeSeconds: Int {
        didSet {
            let v = max(0, min(6, crossfadeSeconds))
            UserDefaults.standard.set(v, forKey: kCrossfadeSec)
            if v != crossfadeSeconds { crossfadeSeconds = v; return }
            applyToPlayer()
        }
    }

    /// BETA v1.2: al dar corazón descargar automáticamente (WiFi guard aparte).
    /// Default true — es la killer feature.
    @Published var autoDownloadFavorites: Bool {
        didSet { UserDefaults.standard.set(autoDownloadFavorites, forKey: kAutoDownloadFavs) }
    }

    /// BETA v1.2: descargar todas las canciones de mis playlists en background.
    /// Default false — puede consumir mucho storage, opt-in explícito.
    @Published var autoDownloadMyPlaylists: Bool {
        didSet { UserDefaults.standard.set(autoDownloadMyPlaylists, forKey: kAutoDownloadMyPls) }
    }

    /// BETA v1.2: descargar todas las canciones de las playlists que sigo.
    /// Default false — puede consumir mucho storage.
    @Published var autoDownloadFollowedPlaylists: Bool {
        didSet { UserDefaults.standard.set(autoDownloadFollowedPlaylists, forKey: kAutoDownloadFollowedPls) }
    }

    /// BETA v1.2: modo offline puro. Cuando true, Player NO llama al extractor
    /// YouTube nunca — sólo reproduce lo que ya está en OfflineLibrary. Ideal
    /// para ahorrar datos móviles o cuando sabes que estás sin red buena.
    @Published var offlineMode: Bool {
        didSet { UserDefaults.standard.set(offlineMode, forKey: kOfflineMode) }
    }

    private init() {
        crossfadeEnabled = UserDefaults.standard.bool(forKey: kCrossfadeOn)
        let s = UserDefaults.standard.integer(forKey: kCrossfadeSec)
        crossfadeSeconds = s == 0 ? 2 : s
        // BETA v1.2.2 — TODO automático por defecto. User puede desactivar en
        // Ajustes si quiere ahorrar storage. WiFi guard sigue evitando gastar datos.
        autoDownloadFavorites = UserDefaults.standard.object(forKey: kAutoDownloadFavs) as? Bool ?? true
        autoDownloadMyPlaylists = UserDefaults.standard.object(forKey: kAutoDownloadMyPls) as? Bool ?? true
        autoDownloadFollowedPlaylists = UserDefaults.standard.object(forKey: kAutoDownloadFollowedPls) as? Bool ?? true
        offlineMode = UserDefaults.standard.bool(forKey: kOfflineMode)
    }

    private func applyToPlayer() {
        let ms = crossfadeEnabled ? crossfadeSeconds * 1000 : 250
        Player.shared.setCrossfadeMs(ms)
    }
}
