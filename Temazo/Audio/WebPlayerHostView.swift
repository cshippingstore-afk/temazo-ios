import SwiftUI
import WebKit

/// View "ancla" 1×1 px que mantiene el WKWebView del WebPlayerEngine
/// dentro del UIWindow del proceso. Si el WebView no está en jerarquía,
/// iOS pausa el audio cuando la app va a background.
///
/// Se monta en MainScreen, oculto detrás de los elementos visuales.
struct WebPlayerHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.isUserInteractionEnabled = false
        container.alpha = 0.01           // invisible pero no transparent total (algunos OS lo pausan)
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
