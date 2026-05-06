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
                            Group {
                                if isCurrent && isPlaying {
                                    Rectangle().fill(Color.black.opacity(0.4))
                                        .overlay(WaveBars().scaleEffect(1.6))
                                }
                            }
                        )

                    HStack(spacing: 4) {
                        Text("#\(rank)")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.bgRoot.opacity(0.8)))
                            .foregroundStyle(rankColor(rank))
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

    private func rankColor(_ r: Int) -> Color {
        switch r {
        case 1: return .medalGold
        case 2: return .medalSilver
        case 3: return .medalBronze
        default: return .neonCyan
        }
    }
}
