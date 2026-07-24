import Foundation

/// BETA v1.2.10 — buffer circular de logs in-app.
///
/// Los `print(...)` del código Swift normalmente sólo se ven con Xcode/3uTools.
/// LogRing captura los mismos mensajes escribiendo también a este buffer accesible
/// desde el UI. En Ajustes → Descargas hay un botón "Ver logs" que enseña las
/// últimas 200 líneas + "Copiar" para pegárselas a soporte.
///
/// Uso:
///   LogRing.shared.log("[DL] START xyz123")
///
/// O como shortcut global:
///   dlog("[DL] START xyz123")
@MainActor
final class LogRing: ObservableObject {
    static let shared = LogRing()
    private let capacity = 200

    /// Líneas almacenadas (más reciente al final).
    @Published private(set) var lines: [String] = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    /// Log de una sola línea. Timestampada.
    func log(_ msg: String) {
        let ts = dateFormatter.string(from: Date())
        let line = "\(ts) \(msg)"
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        // Print además al stdout para Xcode/3uTools/console
        print(line)
    }

    /// Vacía todos los logs (botón "Limpiar").
    func clear() { lines.removeAll() }

    /// Todos los logs como un solo String para el botón "Copiar".
    func joined() -> String { lines.joined(separator: "\n") }
}

/// Shortcut global para no repetir `LogRing.shared.log(...)` en todos lados.
/// Sigue siendo un print normal en cualquier contexto que no sea @MainActor.
func dlog(_ msg: String) {
    Task { @MainActor in
        LogRing.shared.log(msg)
    }
}
