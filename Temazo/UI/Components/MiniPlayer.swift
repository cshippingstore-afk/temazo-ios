import SwiftUI

struct MiniPlayer: View {
    let onExpand: () -> Void
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesRepo
    @State private var showPlaylists = false
    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    var body: some View {
        guard let t = player.state.currentTrack else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                // Slider arrastrable con bolita (NeonSlider) — visible y operable
                NeonSlider(
                    value: Binding(
                        get: { isSeeking ? seekValue : Double(player.state.positionSec) },
                        set: { seekValue = $0 }
                    ),
                    bounds: 0...Double(max(player.state.durationSec, 1)),
                    onEditingChanged: { editing in
                        if editing {
                            isSeeking = true
                        } else {
                            player.seekTo(seconds: Float(seekValue))
                            isSeeking = false
                        }
                    }
                )
                .frame(height: 14)
                .padding(.horizontal, 12)
                .padding(.top, 4)

                HStack(spacing: 10) {
                    CoverImage(url: t.coverUrl, size: 44, cornerRadius: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.neonPink.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: .neonPink.opacity(0.3), radius: 6)
                        .onTapGesture { onExpand() }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        Text(t.artistName ?? "").font(.system(size: 11))
                            .foregroundStyle(.textLow).lineLimit(1)
                    }
                    .onTapGesture { onExpand() }

                    Spacer()

                    Button { showPlaylists = true } label: {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 18))
                            .foregroundStyle(.textMid)
                    }

                    Button { player.prev() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 18))
                            .foregroundStyle(.textMid)
                    }
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22)).foregroundStyle(.white)
                            .padding(8).background(Circle().fill(Color.neonPink))
                            .shadow(color: .neonPink.opacity(0.6), radius: 8)
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 18))
                            .foregroundStyle(.textMid)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .background(Color.bgSurface.opacity(0.6))
            }
            .sheet(isPresented: $showPlaylists) {
                PlaylistPickerSheet(onClose: { showPlaylists = false })
            }
        )
    }
}
