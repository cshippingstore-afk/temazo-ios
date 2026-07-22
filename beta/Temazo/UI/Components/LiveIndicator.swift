import SwiftUI

/// Indicador "LIVE en directo" minimalista: LED pequeño con pulso sutil + texto.
struct LiveIndicator: View {
    let minutes: Int?

    private var color: Color {
        guard let m = minutes else { return .liveGreen }
        if m < 30 { return .liveGreen }
        if m < 120 { return .liveAmber }
        return .liveRed
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // Pulso muy sutil del LED, casi imperceptible
            let pulse = 0.85 + 0.15 * abs(sin(t * 1.5))
            HStack(spacing: 6) {
                // LED pequeño con halo muy ligero
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 14, height: 14)
                        .blur(radius: 2)
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .opacity(pulse)
                }
                .frame(width: 14, height: 14)

                Text("LIVE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(color.opacity(0.95))
                Text("· en directo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.textLow)
            }
            .frame(height: 18)
        }
    }
}
