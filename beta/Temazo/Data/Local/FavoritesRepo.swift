import Foundation
import Combine

/// Repositorio de favoritos local (UserDefaults). Equivalente de Favorites.kt.
@MainActor
final class FavoritesRepo: ObservableObject {
    static let shared = FavoritesRepo()
    private let key = "favorites_track_ids"

    @Published private(set) var ids: Set<Int64> = []

    /// BETA v1.0.0: hook opcional para auto-download.
    /// Se dispara cuando un track pasa de "no favorito" a "favorito".
    /// Requiere el objeto Track completo (no solo el ID) para poder descargarlo.
    var onFavoriteAdded: ((Track) -> Void)?

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

    /// Toggle sólo por ID — usado cuando NO tenemos el Track completo
    /// (ej: sincronización con servidor, sockets remotos, etc.).
    /// Este toggle NO dispara auto-descarga aunque marque como favorito, porque
    /// no tenemos el Track para pasar a DownloadManager.
    func toggle(_ id: Int64) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        save()
    }

    /// Wrapper con keyword param — para uso desde FavToggle helper.
    func toggle(trackId: Int64) { toggle(trackId) }

    /// v1.0.0 BETA: toggle CON Track completo. Al añadir favorito, dispara
    /// auto-download vía DownloadManager. Al quitar, NO borra descarga (el user
    /// decide desde Descargas si quiere liberar espacio).
    func toggleWithTrack(_ track: Track) {
        let wasFavorite = ids.contains(Int64(track.id))
        toggle(Int64(track.id))
        if !wasFavorite {
            // Se acaba de marcar como favorito → auto-descarga
            print("[FavRepo] favorito añadido → auto-download \(track.title)")
            onFavoriteAdded?(track)
        }
    }

    /// Reemplaza el set local con la lista remota (al login).
    func setRemote(_ remote: [Int64]) {
        ids = Set(remote)
        save()
    }

    func replaceAll(_ remote: [Int64]) { setRemote(remote) }

    func clear() {
        ids = []
        save()
    }
}
