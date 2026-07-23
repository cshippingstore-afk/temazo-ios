import Foundation
import SwiftUI

/// Toggle de favorito unificado: requiere sesión iniciada.
/// Si no hay sesión: dispara notificación para que MainScreen muestre toast y cambie
/// a la pestaña "Mi cuenta". Si hay sesión: actualiza repo local + POST al server.
@MainActor
enum FavToggle {
    /// BETA v1: overload con Track completo — dispara auto-download del audio
    /// cuando el user pasa de no-favorito a favorito (WiFi guard en DownloadManager).
    /// Preferir esta versión sobre `toggle(trackId:)` siempre que tengamos el Track.
    static func toggle(_ track: Track,
                       favRepo: FavoritesRepo,
                       onLoginRequired: @escaping () -> Void = {}) {
        if AuthRepository.shared.currentUser == nil {
            NotificationCenter.default.post(name: .temazoToastLoginRequired, object: nil)
            onLoginRequired()
            return
        }
        // optimista local (dispara onFavoriteAdded → auto-download si aplica)
        favRepo.toggleWithTrack(track)
        Task {
            do {
                _ = try await TemazoAPI.shared.favToggle(track.id)
            } catch {
                // revertir si falla — sin re-disparar hook (revert no descarga)
                favRepo.toggle(trackId: track.id)
            }
        }
    }

    /// Legacy: cuando solo tenemos el ID (deep-links, sockets remotos, etc.).
    /// No dispara auto-download porque no hay metadata para persistir.
    static func toggle(trackId: Int64,
                       favRepo: FavoritesRepo,
                       onLoginRequired: @escaping () -> Void = {}) {
        if AuthRepository.shared.currentUser == nil {
            NotificationCenter.default.post(name: .temazoToastLoginRequired, object: nil)
            onLoginRequired()
            return
        }
        favRepo.toggle(trackId: trackId)
        Task {
            do {
                _ = try await TemazoAPI.shared.favToggle(trackId)
            } catch {
                favRepo.toggle(trackId: trackId)
            }
        }
    }
}

extension Notification.Name {
    /// Disparada cuando el server confirma que se cerró sesión por su lado
    /// (token expirado, etc.) — la UI puede limpiar estado local.
    static let temazoSessionExpired = Notification.Name("temazoSessionExpired")

    /// BETA v1.2.1: pedir mostrar un toast al usuario. userInfo["text"] = String.
    /// MainScreen lo captura y lo pinta durante 2s.
    static let temazoShowToast = Notification.Name("temazoShowToast")
}
