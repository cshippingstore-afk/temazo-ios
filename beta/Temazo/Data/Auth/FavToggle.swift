import Foundation
import SwiftUI

/// Toggle de favorito unificado: requiere sesión iniciada.
/// Si no hay sesión: dispara notificación para que MainScreen muestre toast y cambie
/// a la pestaña "Mi cuenta". Si hay sesión: actualiza repo local + POST al server.
@MainActor
enum FavToggle {
    static func toggle(trackId: Int64,
                       favRepo: FavoritesRepo,
                       onLoginRequired: @escaping () -> Void = {}) {
        if AuthRepository.shared.currentUser == nil {
            NotificationCenter.default.post(name: .temazoToastLoginRequired, object: nil)
            onLoginRequired()
            return
        }
        // optimista local
        favRepo.toggle(trackId: trackId)
        Task {
            do {
                _ = try await TemazoAPI.shared.favToggle(trackId)
            } catch {
                // revertir si falla
                favRepo.toggle(trackId: trackId)
            }
        }
    }
}

extension Notification.Name {
    /// Disparada cuando el server confirma que se cerró sesión por su lado
    /// (token expirado, etc.) — la UI puede limpiar estado local.
    static let temazoSessionExpired = Notification.Name("temazoSessionExpired")
}
