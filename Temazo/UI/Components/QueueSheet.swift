import SwiftUI

/// Cola de reproducción actual. Cada item es tappable para saltar a esa canción.
/// La actual está resaltada.
struct QueueSheet: View {
    let onClose: () -> Void
    @EnvironmentObject var player: Player

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 4).padding(.top, 10)
            HStack {
                Text("En cola")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(player.state.queue.count) canciones")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMid)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(player.state.queue.enumerated()), id: \.offset) { idx, t in
                        let isCurrent = idx == player.state.index
                        Button {
                            if !isCurrent {
                                player.playTrack(t, queue: player.state.queue, index: idx, source: player.state.source)
                                onClose()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: t.coverUrl, size: 44, cornerRadius: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title)
                                        .font(.system(size: 13, weight: isCurrent ? .bold : .semibold))
                                        .foregroundStyle(isCurrent ? Color.neonPink : .white)
                                        .lineLimit(1)
                                    Text(t.artistName ?? "")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.textLow)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if isCurrent {
                                    Image(systemName: player.state.isPlaying ? "waveform" : "pause.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.neonPink)
                                }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(isCurrent ? Color.neonPink.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.04, blue: 0.12))
    }
}
