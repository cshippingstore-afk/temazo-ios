import SwiftUI

/// Indicador "LIVE" tipo cartel encendido con glow neon que pulsa.
struct LiveIndicator: View {
    let minutes: Int?

    private var color: Color {
        guard let m = minutes else { return .liveGreen }
        if m < 30 { return .liveGreen }
        if m < 120 { return .liveAmber }
        return .liveRed
    }

    private var subtitle: String {
        if let m = minutes { return "actualizado hace \(m) min" }
        return "en directo"
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = 0.6 + 0.4 * abs(sin(t * 2.0))
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.30))
                        .frame(width: 22, height: 22)
                        .scaleEffect(1.0 + pulse * 0.6)
                        .blur(radius: 3)
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .shadow(color: color.opacity(pulse), radius: 8)
                        .shadow(color: color.opacity(pulse * 0.7), radius: 16)
                }
                .frame(width: 24, height: 24)

                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(color)
                        .shadow(color: color.opacity(pulse), radius: 6)
                    Text("·")
                        .foregroundStyle(.textMuted)
                        .font(.system(size: 12))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.textMid)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.bgSurface.opacity(0.8))
                    .overlay(
                        Capsule().stroke(color.opacity(0.4 + pulse * 0.3), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.2 + pulse * 0.2), radius: 12)
            )
        }
        .frame(height: 36)
    }
}
