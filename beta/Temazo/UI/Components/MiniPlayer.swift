import SwiftUI

/// MiniPlayer rediseñado (igual que Android v1.48+):
/// - Sin botones skip prev/next ni slider (gestos lo hacen)
/// - Botón play/pause con anillo circular de progreso
/// - Botón corazón a la izquierda del play
/// - Todo el row clickable → expandir
/// - Swipe ↑ expand · Swipe ←/→ next/prev
struct MiniPlayer: View {
    let onExpand: () -> Void
    let onCoverClick: () -> Void
    let onArtistClick: () -> Void
    let onAddToPlaylist: () -> Void
    let onLoadPlaylist: () -> Void   // no usado en UI (compat), gestionado por la pestaña Playlists

    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesRepo
    @State private var dragV: CGFloat = 0
    @State private var dragH: CGFloat = 0

    var body: some View {
        guard let t = player.state.currentTrack else { return AnyView(EmptyView()) }
        let isFav = favorites.contains(t.id)
        let progress: Double = {
            let dur = max(Double(player.state.durationSec), 1)
            return min(max(Double(player.state.positionSec) / dur, 0), 1)
        }()

        return AnyView(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.neonPink.opacity(0.55), Color.neonPurple.opacity(0.35), Color.neonPink.opacity(0.55)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
                .shadow(color: Color.neonPink.opacity(0.6), radius: 4, y: -1)

                HStack(spacing: 8) {
                    ZStack {
                        CoverImage(url: t.coverUrl, size: 48, cornerRadius: 6)
                        // Cinta diagonal proporcionada para cover mini de 48dp.
                        SourceRibbon(
                            source: player.state.source,
                            trackId: t.id,
                            ribbonWidth: 56,
                            ribbonHeight: 14,
                            fontSize: 8
                        )
                        .frame(width: 48, height: 48)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.neonPink.opacity(0.4), lineWidth: 1))
                    .shadow(color: Color.neonPink.opacity(0.3), radius: 6)
                    // Paridad Android: tap en el cover → álbum si existe, si no expand.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if t.albumId != nil || (t.albumSlug?.isEmpty == false) {
                            onCoverClick()
                        } else {
                            onExpand()
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        MarqueeText(text: t.title,
                                    font: .system(size: 14, weight: .semibold),
                                    color: .white, velocity: 30)
                        MarqueeText(text: t.artistName ?? "",
                                    font: .system(size: 12),
                                    color: Color.textLow, velocity: 25)
                            // Paridad Android: tap en el nombre del artista → ArtistScreen.
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if t.artistId != nil || (t.artistSlug?.isEmpty == false) {
                                    onArtistClick()
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 36)

                    // Añadir a playlist
                    Button(action: onAddToPlaylist) {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Spacer().frame(width: 2)

                    // Corazón (Me gusta) — beta: dispara auto-download al favoritar
                    Button(action: {
                        FavToggle.toggle(t, favRepo: favorites)
                    }) {
                        Image(systemName: isFav ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundStyle(isFav ? Color.neonPink : Color.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Spacer().frame(width: 8)

                    // Play/Pause con anillo circular de progreso
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 2)
                            .frame(width: 44, height: 44)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.neonPink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: progress)
                        Button(action: { player.togglePlay() }) {
                            Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { onExpand() }
                // Gestos: swipe vertical hacia arriba expande, swipe horizontal cambia canción.
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { val in
                            dragV = val.translation.height
                            dragH = val.translation.width
                        }
                        .onEnded { val in
                            let dx = val.translation.width
                            let dy = val.translation.height
                            if abs(dy) > abs(dx) {
                                // vertical
                                if dy < -80 { onExpand() }
                            } else {
                                // horizontal
                                if dx < -120 { player.next() }
                                else if dx > 120 { player.prev() }
                            }
                            dragV = 0; dragH = 0
                        }
                )
            }
            .background(
                ZStack {
                    Color.bgRoot
                    LinearGradient(
                        colors: [
                            Color.neonPink.opacity(0.10),
                            Color.neonPurple.opacity(0.06),
                            Color.bgSurface.opacity(0.0)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            )
        )
    }
}
