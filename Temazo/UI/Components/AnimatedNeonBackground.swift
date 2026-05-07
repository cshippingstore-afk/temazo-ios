import SwiftUI

/// Fondo neon SUAVE: blobs grandes, lentos, poco saturados.
/// Se nota apenas como ambiente, no compite con el contenido.
struct AnimatedNeonBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Color.bgRoot.ignoresSafeArea()

                // 3 blobs muy grandes, opacidad baja, movimiento muy lento
                blob(
                    color: hueShift(t * 0.008, base: 0.92, sat: 0.55, bri: 0.40),
                    cx: 0.30 + 0.10 * sin(t * 0.025),
                    cy: 0.20 + 0.08 * cos(t * 0.020),
                    radiusFrac: 0.65
                )
                blob(
                    color: hueShift(t * 0.006 + 0.33, base: 0.75, sat: 0.55, bri: 0.35),
                    cx: 0.75 + 0.10 * cos(t * 0.022),
                    cy: 0.65 + 0.10 * sin(t * 0.028),
                    radiusFrac: 0.60
                )
                blob(
                    color: hueShift(t * 0.005 + 0.66, base: 0.55, sat: 0.50, bri: 0.30),
                    cx: 0.20 + 0.08 * cos(t * 0.018),
                    cy: 0.85 + 0.06 * sin(t * 0.016),
                    radiusFrac: 0.55
                )

                // Velo oscuro fuerte para que el fondo sea solo ambiente
                Color.black.opacity(0.78).ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
    }

    private func blob(color: Color, cx: Double, cy: Double, radiusFrac: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.55), color.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: w * radiusFrac
                    )
                )
                .frame(width: w * radiusFrac * 2, height: w * radiusFrac * 2)
                .position(x: w * cx, y: h * cy)
                .blur(radius: 80)
        }
    }

    private func hueShift(_ phase: Double, base: Double, sat: Double, bri: Double) -> Color {
        let h = (base + 0.30 * sin(phase * .pi * 2)).truncatingRemainder(dividingBy: 1.0)
        let hue = h < 0 ? h + 1 : h
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
}
