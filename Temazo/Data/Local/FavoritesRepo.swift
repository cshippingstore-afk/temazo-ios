import Foundation
import Combine

/// Repositorio de favoritos local (UserDefaults). Equivalente de Favorites.kt.
@MainActor
final class FavoritesRepo: ObservableObject {
    static let shared = FavoritesRepo()
    private let key = "favorites_track_ids"

    @Published private(set) var ids: Set<Int64> = []

    private init() {
        load()
    }

    private func load() {
        let arr = UserDefaults.standard.array(forKey: key) as? [Int64] ?? []
        ids = Set(arr)
    }

    private func save() {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    func contains(_ id: Int64) -> Bool { ids.contains(id) }

    func toggle(_ id: Int64) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        save()
        // Sync remoto best-effort
        Task { try? await TemazoAPI.shared.favToggle(id) }
    }

    /// Reemplaza el set local con la lista remota (al login).
    func setRemote(_ remote: [Int64]) {
        ids = Set(remote)
        save()
    }
}
