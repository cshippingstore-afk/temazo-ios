import SwiftUI

/// MarqueeText — desplazamiento horizontal infinito si el texto no cabe.
/// Implementado con withAnimation(repeatForever) — no usa TimelineView a 60fps,
/// así Core Animation se encarga de la interpolación y es mucho más ligero.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 14, weight: .semibold)
    var color: Color = .white
    var velocity: CGFloat = 30   // points/sec
    var gap: CGFloat = 40

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animate: Bool = false

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textWidth > geo.size.width
            let totalShift: CGFloat = textWidth + gap

            HStack(spacing: gap) {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize()
                    .background(WidthReader())
                if needsScroll {
                    Text(text).font(font).foregroundStyle(color).fixedSize()
                }
            }
            .offset(x: needsScroll && animate ? -totalShift : 0)
            .animation(
                needsScroll
                ? .linear(duration: Double(totalShift / max(velocity, 1))).repeatForever(autoreverses: false)
                : .default,
                value: animate
            )
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .onPreferenceChange(WidthKey.self) { w in
                textWidth = w
                containerWidth = geo.size.width
                if w > geo.size.width {
                    // Pequeño delay para que SwiftUI termine de medir antes de arrancar
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { animate = true }
                } else {
                    animate = false
                }
            }
        }
        .frame(height: 20)
    }
}

private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct WidthReader: View {
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: WidthKey.self, value: g.size.width)
        }
    }
}
