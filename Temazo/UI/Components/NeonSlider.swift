import SwiftUI

/// Slider personalizado con bolita visible neon — para arrastrar en el reproductor.
/// SwiftUI Slider nativo a veces oculta el thumb sobre tracks oscuros; este lo hace
/// siempre visible y con glow.
struct NeonSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let total = bounds.upperBound - bounds.lowerBound
            let displayValue = isDragging ? dragValue : value
            let normalized = total > 0 ? (displayValue - bounds.lowerBound) / total : 0
            let clamped = max(0, min(1, normalized))
            let trackWidth = geo.size.width
            let thumbX = clamped * trackWidth

            ZStack(alignment: .leading) {
                // Track de fondo
                RoundedRectangle(cornerRadius: trackHeight/2)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackHeight)

                // Track relleno (neon pink con glow)
                RoundedRectangle(cornerRadius: trackHeight/2)
                    .fill(LinearGradient(colors: [.neonPink, .neonPurple],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, thumbX), height: trackHeight)
                    .shadow(color: .neonPink.opacity(0.6), radius: 4, y: 0)

                // Bolita arrastrable
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .neonPink.opacity(0.8), radius: 6)
                    .overlay(
                        Circle().stroke(Color.neonPink, lineWidth: 2)
                    )
                    .offset(x: thumbX - thumbSize/2)
            }
            .frame(height: max(thumbSize, trackHeight))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let pct = max(0, min(1, v.location.x / trackWidth))
                        dragValue = bounds.lowerBound + pct * total
                    }
                    .onEnded { _ in
                        value = dragValue
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 22)
    }
}
