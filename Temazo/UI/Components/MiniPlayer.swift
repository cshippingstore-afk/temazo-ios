import SwiftUI

/// MiniPlayer — réplica del Android.
/// - Tap en cover → álbum (si tiene album_id)
/// - Tap en artista → perfil del artista (si tiene artist_id/slug)
/// - Tap en título → expand FullPlayer
/// - Swipe up sobre la fila superior → expand FullPlayer
/// - Botones playlist apilados verticalmente: arriba "+" añadir, abajo "▶" cargar
struct MiniPlayer: View {
    let onExpand: () -> Void
    let onCoverClick: () -> Void
    let onArtistClick: () -> Void
    let onAddToPlaylist: () -> Void
    let onLoadPlaylist: () -> Void

    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesRepo
    @State private var seekValue: Double = 0
    @State private var isSeeking = false
    @State private var dragAccum: CGFloat = 0

    var body: some View {
        guard let t = player.state.currentTrack else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                topRow(t)
                NeonSlider(
                    value: Binding(
                        get: { isSeeking ? seekValue : Double(player.state.positionSec) },
                        set: { seekValue = $0 }
                    ),
                    bounds: 0...Double(max(player.state.durationSec, 1)),
                    onEditingChanged: { editing in
                        if editing { isSeeking = true }
                        else { player.seekTo(seconds: Float(seekValue)); isSeeking = false }
                    }
                )
                .frame(height: 14)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
            .background(.ultraThinMaterial)
            .background(Color.bgSurface.opacity(0.6))
        )
    }

    @ViewBuilder
    private func topRow(_ t: Track) -> some View {
        HStack(spacing: 10) {
            CoverImage(url: t.coverUrl, size: 44, cornerRadius: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.neonPink.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: Color.neonPink.opacity(0.3), radius: 6)
                .onTapGesture {
                    if t.albumId != nil || (t.albumSlug?.isEmpty == false) {
                        onCoverClick()
                    } else {
                        onExpand()
                    }
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(t.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                    .onTapGesture { onExpand() }
                Text(t.artistName ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textLow).lineLimit(1)
                    .onTapGesture {
                        if t.artistId != nil || (t.artistSlug?.isEmpty == false) {
                            onArtistClick()
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Dos botones playlist apilados (mismo ancho que un IconButton)
            VStack(spacing: 0) {
                Button { onAddToPlaylist() } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 32, height: 24)
                }
                Button { onLoadPlaylist() } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 32, height: 24)
                }
            }

            Button { player.prev() } label: {
                Image(systemName: "backward.fill").font(.system(size: 18))
                    .foregroundStyle(Color.textMid)
            }
            Button { player.togglePlay() } label: {
                Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22)).foregroundStyle(.white)
                    .padding(8).background(Circle().fill(Color.neonPink))
                    .shadow(color: Color.neonPink.opacity(0.6), radius: 8)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 18))
                    .foregroundStyle(Color.textMid)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .local)
                .onChanged { val in
                    dragAccum = val.translation.height
                }
                .onEnded { val in
                    if val.translation.height < -80 { onExpand() }
                    dragAccum = 0
                }
        )
    }
}
