import SwiftUI
import UIKit

/// Swipe-back desde el borde izquierdo usando UIScreenEdgePanGestureRecognizer
/// nativo — el mismo que usa UINavigationController. Funciona con scrolls anidados
/// porque iOS prioriza el screen edge pan sobre cualquier scroll.
struct SwipeBackModifier: ViewModifier {
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content.overlay(EdgePanRecognizer(onBack: onBack).allowsHitTesting(true))
    }
}

private struct EdgePanRecognizer: UIViewRepresentable {
    let onBack: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onBack: onBack) }

    func makeUIView(context: Context) -> UIView {
        let v = PassthroughView()
        let gr = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        gr.edges = .left
        gr.delegate = context.coordinator
        v.addGestureRecognizer(gr)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBack = onBack
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBack: () -> Void
        private var fired: Bool = false

        init(onBack: @escaping () -> Void) { self.onBack = onBack }

        @objc func handle(_ gr: UIScreenEdgePanGestureRecognizer) {
            guard let view = gr.view else { return }
            let tx = gr.translation(in: view).x
            let vx = gr.velocity(in: view).x

            switch gr.state {
            case .began:
                fired = false
            case .changed:
                // Dispara en cuanto cruza 60pt OR velocidad > 250 px/s — antes de soltar
                if !fired && (tx > 60 || vx > 250) {
                    fired = true
                    onBack()
                }
            case .ended, .cancelled, .failed:
                if !fired && tx > 30 {
                    fired = true
                    onBack()
                }
                fired = false
            default: break
            }
        }

        // Permite coexistir con scrolls — el edge pan tiene preferencia
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return false
        }

        // Que el edge pan FALLE a otros gestos (ej. scroll) → permite que el edge gane
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            return false
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

/// Una UIView que deja pasar los toques que no toca un gesture suyo.
private final class PassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Sólo capturar en el borde izquierdo (24pt) — el resto pasa al contenido
        return point.x < 24
    }
}

extension View {
    /// Swipe-back desde el borde izquierdo — pop del detail stack.
    func swipeBack(_ onBack: @escaping () -> Void) -> some View {
        modifier(SwipeBackModifier(onBack: onBack))
    }
}
