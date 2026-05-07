import SwiftUI

struct TemazoTopBar: View {
    let isPlaying: Bool

    var body: some View {
        ZStack {
            // Logo centrado, más grande
            Image("logo_temazo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 56)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                EqualizerBars(isActive: isPlaying)
                    .padding(.trailing, 4)
            }
        }
        .frame(height: 56)
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
                        .frame(width: 3, height: 22 * h)
                }
            }
            .frame(height: 26)
        }
    }
}
