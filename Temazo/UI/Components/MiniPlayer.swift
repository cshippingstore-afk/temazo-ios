import SwiftUI

struct MiniPlayer: View {
    let onExpand: () -> Void
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesRepo

    var body: some View {
        guard let t = player.state.currentTrack else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                // Progress bar fina arriba con glow neon
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.borderSoft).frame(height: 2)
                        Rectangle()
                            .fill(LinearGradient(colors: [.neonPink, .neonPurple],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geo.size.width * progress), height: 2)
                            .shadow(color: .neonPink.opacity(0.7), radius: 4, y: 0)
                    }
                }
                .frame(height: 2)

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
                        HStack(spacing: 4) {
                            Text(t.artistName ?? "").font(.system(size: 11))
                                .foregroundStyle(.textLow).lineLimit(1)
                            if player.state.loadingState != .playing {
                                Text("· \(player.state.loadingState.rawValue)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(player.state.loadingState == .failed ? .liveRed : .neonCyan)
                            }
                        }
                        if player.state.loadingState == .failed,
                           let err = player.state.lastError {
                            Text(err).font(.system(size: 9))
                                .foregroundStyle(.liveRed).lineLimit(2)
                        }
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
                            .shadow(color: .neonPink.opacity(0.6), radius: 8)
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
