import SwiftUI

/// Modifier que añade swipe-back desde el borde izquierdo.
/// Empieza el drag en los primeros 24 puntos de ancho y dispara onBack si el
/// drag horizontal supera 80 puntos (y no es predominantemente vertical).
struct SwipeBackModifier: ViewModifier {
    let onBack: () -> Void
    @State private var startedAtEdge: Bool = false

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { val in
                        if val.startLocation.x < 24 { startedAtEdge = true }
                    }
                    .onEnded { val in
                        defer { startedAtEdge = false }
                        guard startedAtEdge else { return }
                        let dx = val.translation.width
                        let dy = val.translation.height
                        if abs(dx) > abs(dy), dx > 80 { onBack() }
                    }
            )
    }
}

extension View {
    /// Swipe-back desde el borde izquierdo → pop. Usar en pantallas de detalle.
    func swipeBack(_ onBack: @escaping () -> Void) -> some View {
        modifier(SwipeBackModifier(onBack: onBack))
    }
}
