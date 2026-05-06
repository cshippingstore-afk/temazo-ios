import SwiftUI

struct TemazoTopBar: View {
    let isPlaying: Bool

    var body: some View {
        HStack {
            // Wordmark "TEMAZO" — imagen real (mismo PNG que Android)
            Image("logo_temazo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 36)
            Spacer()
            EqualizerBars(isActive: isPlaying)
        }
    }
}

private struct EqualizerBars: View {
    let isActive: Bool
    private let bars = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: isActive ? 0.06 : nil, paused: !isActive)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let h: CGFloat = isActive
                        ? CGFloat(0.3 + 0.7 * abs(sin(t * 4 + Double(i) * 0.7)))
                        : 0.4
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isActive ? Color.neonPink : Color.textLow)
                        .frame(width: 3, height: 18 * h)
                }
            }
            .frame(height: 22)
        }
    }
}
