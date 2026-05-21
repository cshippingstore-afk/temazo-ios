import SwiftUI

/// Bottom sheet de opciones para una canción (long-press en TrackRow).
struct TrackOptionsSheet: View {
    let track: Track
    let isFavorite: Bool
    var onDismiss: () -> Void
    var onToggleFav: () -> Void
    var onAddToPlaylist: () -> Void
    var onAddToQueue: () -> Void
    var onGoToArtist: () -> Void
    var onGoToAlbum: () -> Void
    var onShare: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                CoverImage(url: track.coverUrl, size: 56, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(track.artistName ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.65)).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)

            row(icon: isFavorite ? "heart.fill" : "heart",
                label: isFavorite ? "Quitar de Me gusta" : "Añadir a Me gusta",
                tint: isFavorite ? Color.neonPink : .white) {
                onToggleFav(); onDismiss()
            }
            row(icon: "plus.rectangle.on.rectangle", label: "Añadir a playlist") {
                onAddToPlaylist(); onDismiss()
            }
            row(icon: "text.line.first.and.arrowtriangle.forward", label: "Añadir a la cola") {
                onAddToQueue(); onDismiss()
            }
            if track.artistId != nil || (track.artistSlug?.isEmpty == false) {
                row(icon: "person.fill", label: "Ir al artista") {
                    onGoToArtist(); onDismiss()
                }
            }
            if track.albumId != nil || (track.albumSlug?.isEmpty == false) {
                row(icon: "square.stack.fill", label: "Ir al álbum") {
                    onGoToAlbum(); onDismiss()
                }
            }
            row(icon: "square.and.arrow.up", label: "Compartir") {
                onShare(); onDismiss()
            }
            Spacer().frame(height: 12)
        }
        .background(Color(red: 0.10, green: 0.04, blue: 0.18))
        .presentationDetents([.fraction(0.55), .medium])
    }

    @ViewBuilder
    private func row(icon: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint).frame(width: 24)
                Text(label).font(.system(size: 15)).foregroundStyle(tint)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}
