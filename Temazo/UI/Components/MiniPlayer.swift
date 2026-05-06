import SwiftUI

struct MiniPlayer: View {
    let onExpand: () -> Void
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesRepo

    var body: some View {
        guard let t = player.state.currentTrack else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                // Progress bar fina arriba
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.borderSoft).frame(height: 2)
                        Rectangle().fill(Color.neonPink)
                            .frame(width: max(0, geo.size.width * progress), height: 2)
                    }
                }
                .frame(height: 2)

                HStack(spacing: 10) {
                    CoverImage(url: t.coverUrl, size: 44, cornerRadius: 6)
                        .onTapGesture { onExpand() }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        Text(t.artistName ?? "").font(.system(size: 11))
                            .foregroundStyle(.textLow).lineLimit(1)
                    }
                    .onTapGesture { onExpand() }

                    Spacer()

                    Button { player.prev() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 18))
                            .foregroundStyle(.textMid)
                    }
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22)).foregroundStyle(.white)
                            .padding(8).background(Circle().fill(Color.neonPink))
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 18))
                            .foregroundStyle(.textMid)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.bgSurface)
            }
        )
    }

    private var progress: CGFloat {
        let d = player.state.durationSec
        return d > 0 ? CGFloat(player.state.positionSec / d) : 0
    }
}
