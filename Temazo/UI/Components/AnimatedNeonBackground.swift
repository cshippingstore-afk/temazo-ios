import SwiftUI

/// Fondo neon animado: dos blobs gigantes de gradient se mueven y cambian de color
/// suavemente detrás del UI. Da el efecto "neon vivo" tipo discoteca / web Temazo.
struct AnimatedNeonBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // Tres blobs grandes que rotan + cambian de color HSB en ciclos largos
            ZStack {
                Color.bgRoot.ignoresSafeArea()

                blob(
                    color: hueShift(t * 0.04, base: 0.92, sat: 0.85, bri: 0.65),  // pinks → purples
                    cx: 0.30 + 0.25 * sin(t * 0.13),
                    cy: 0.20 + 0.18 * cos(t * 0.10),
                    radius: 0.55
                )
                blob(
                    color: hueShift(t * 0.03 + 0.33, base: 0.75, sat: 0.85, bri: 0.55),  // purples → cyan
                    cx: 0.75 + 0.20 * cos(t * 0.11),
                    cy: 0.65 + 0.22 * sin(t * 0.14),
                    radius: 0.50
                )
                blob(
                    color: hueShift(t * 0.02 + 0.66, base: 0.50, sat: 0.85, bri: 0.55),  // cyan → green
                    cx: 0.20 + 0.15 * cos(t * 0.09),
                    cy: 0.85 + 0.12 * sin(t * 0.08),
                    radius: 0.45
                )

                // Veil oscuro encima para que el contenido se lea bien
                Color.black.opacity(0.52).ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
    }

    private func blob(color: Color, cx: Double, cy: Double, radius: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.85), color.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: w * radius
                    )
                )
                .frame(width: w * radius * 2, height: w * radius * 2)
                .position(x: w * cx, y: h * cy)
                .blur(radius: 60)
        }
    }

    /// Devuelve un Color cuyo hue se desliza suavemente con el tiempo
    private func hueShift(_ phase: Double, base: Double, sat: Double, bri: Double) -> Color {
        let h = (base + 0.5 * sin(phase * .pi * 2)).truncatingRemainder(dividingBy: 1.0)
        let hue = h < 0 ? h + 1 : h
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
}
