import SwiftUI

/// Modifier de conveniencia — long-press en cualquier vista abre el TrackOptionsSheet
/// (fav, playlist, cola, ir a artista/álbum, share, recomendar, REPORTAR, y ADMIN).
///
/// Uso:
///     row(track).trackLongPress(track)
///
/// Diseñado para reemplazar el patron repetido:
///     .onLongPressGesture(minimumDuration: 0.4) {
///         TrackOptionsBus.shared.show(track)
///     }
///
/// Todas las listas de tracks (Favoritos, Historial, Álbum, Playlist,
/// Downloads, Search, Home, etc.) deben aplicarlo para exponer las acciones
/// admin/report de forma uniforme.
struct TrackLongPressModifier: ViewModifier {
    let track: Track
    var minimumDuration: Double = 0.4

    func body(content: Content) -> some View {
        content.onLongPressGesture(minimumDuration: minimumDuration) {
            TrackOptionsBus.shared.show(track)
        }
    }
}

extension View {
    /// Long-press → TrackOptionsSheet. Incluye acciones fav + admin + report.
    func trackLongPress(_ track: Track, minimumDuration: Double = 0.4) -> some View {
        modifier(TrackLongPressModifier(track: track, minimumDuration: minimumDuration))
    }
}
