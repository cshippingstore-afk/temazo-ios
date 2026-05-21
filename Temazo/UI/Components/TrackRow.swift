import SwiftUI

struct TrackRow: View {
    let track: Track
    let rank: Int?
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    @EnvironmentObject var favorites: FavoritesRepo

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            // Long-press → abrir TrackOptionsSheet via bus global
            .onLongPressGesture(minimumDuration: 0.4) {
                TrackOptionsBus.shared.show(track)
            }
            // Swipe ← toggle Me gusta
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { v in
                        if v.translation.width < -120 && abs(v.translation.height) < 40 {
                            FavToggle.toggle(trackId: track.id, favRepo: favorites)
                        }
                    }
            )
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: 10) {
                if let r = rank {
                    Text("\(r)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(rankColor(r))
                        .frame(width: 28, alignment: .center)
                }

                CoverImage(url: track.coverUrl, size: 44, cornerRadius: 6)
                    .overlay(
                        Group {
                            if isCurrent && isPlaying {
                                Rectangle().fill(Color.black.opacity(0.45))
                                    .overlay(WaveBars())
                            }
                        }
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isCurrent ? .neonPink : .white)
                        .lineLimit(1)
                    Text(track.artistName ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.textLow)
                        .lineLimit(1)
                }
                Spacer()
                if !track.displayDuration.isEmpty {
                    Text(track.displayDuration)
                        .font(.system(size: 11)).foregroundStyle(.textMuted)
                }
                Image(systemName: favorites.contains(track.id) ? "heart.fill" : "heart")
                    .foregroundStyle(favorites.contains(track.id) ? Color.neonPink : Color.textLow)
                    .font(.system(size: 14))
                    .onTapGesture { favorites.toggle(track.id) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCurrent
                        ? LinearGradient(colors: [Color.neonPink.opacity(0.15), Color.neonPurple.opacity(0.08)],
                                          startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.bgSurface, Color.bgSurface], startPoint: .leading, endPoint: .trailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isCurrent ? Color.neonPink.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
            .shadow(color: isCurrent ? Color.neonPink.opacity(0.3) : Color.clear, radius: 10)
    }

    private func rankColor(_ r: Int) -> Color {
        switch r {
        case 1: return .medalGold
        case 2: return .medalSilver
        case 3: return .medalBronze
        default: return .textLow
        }
    }
}

struct CoverImage: View {
    let url: String?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(Color.bgSurfaceHi)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.textMuted))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct WaveBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: 2, height: CGFloat(4 + 8 * abs(sin(t * 5 + Double(i) * 0.5))))
                }
            }
        }
    }
}
