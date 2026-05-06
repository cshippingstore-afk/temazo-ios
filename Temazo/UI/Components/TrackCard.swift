import SwiftUI

struct TrackCard: View {
    let track: Track
    let rank: Int
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    CoverImage(url: track.coverUrl, size: 150, cornerRadius: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isCurrent ? Color.neonPink : Color.borderSoft.opacity(0.5),
                                        lineWidth: isCurrent ? 2 : 1)
                        )
                        .overlay(
                            Group {
                                if isCurrent && isPlaying {
                                    Rectangle().fill(Color.black.opacity(0.4))
                                        .overlay(WaveBars().scaleEffect(1.6))
                                }
                            }
                        )
                        .shadow(color: isCurrent ? Color.neonPink.opacity(0.6) : Color.clear,
                                radius: isCurrent ? 16 : 0, y: 0)
                        .shadow(color: rank <= 3 ? rankGlow(rank).opacity(0.35) : Color.clear,
                                radius: 12)

                    HStack(spacing: 4) {
                        Text("#\(rank)")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.bgRoot.opacity(0.85)))
                            .foregroundStyle(rankGlow(rank))
                            .shadow(color: rankGlow(rank).opacity(0.5), radius: 4)
                    }
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artistName ?? "")
                    .font(.system(size: 11)).foregroundStyle(.textLow)
                    .lineLimit(1)
            }
            .frame(width: 150)
        }
        .buttonStyle(.plain)
    }

    private func rankGlow(_ r: Int) -> Color {
        switch r {
        case 1: return .medalGold
        case 2: return .medalSilver
        case 3: return .medalBronze
        default: return .neonCyan
        }
    }
}
