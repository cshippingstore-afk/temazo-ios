import SwiftUI
import WebKit

/// View "ancla" 1×1 px que mantiene el WKWebView del WebPlayerEngine
/// dentro del UIWindow del proceso. Si el WebView no está en jerarquía
/// de vistas, iOS pausa el JS y el audio cuando la app va a background.
///
/// Se monta en MainScreen al inicio del ZStack, oculto detrás de toda la UI.
struct WebPlayerHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        // Tamaño 4×4 px (no 1×1) — iOS considera "hidden" los WebViews de 1px
        // y pausa el audio. 4×4 es el mínimo seguro que mantiene la reproducción.
        // alpha 0.01 lo hace prácticamente invisible al ojo humano.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        container.isUserInteractionEnabled = false
        container.alpha = 0.01
        container.backgroundColor = .clear
        container.clipsToBounds = true

        let webView = WebPlayerEngine.shared.webView!
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // El WebView vive en el shared engine; el container sólo lo ancla al window.
    }
}
