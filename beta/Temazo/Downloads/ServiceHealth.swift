import Foundation
import Combine

/// BETA v1.2.7 — Circuit breaker por servicio (extractor local + proxy VPS).
///
/// Objetivo: si un servicio falla N veces seguidas, marcarlo como DEGRADED
/// durante un cooldown (5 min). Durante ese tiempo, DownloadManager y Player
/// EVITAN llamarlo y saltan al siguiente en cadena.
///
/// Evita el patrón "58 fails cascade" — cuando YouTube banea IP, no seguimos
/// bombardeando con retries que solo empeoran la situación.
@MainActor
final class ServiceHealth: ObservableObject {
    static let shared = ServiceHealth()

    enum State: Equatable {
        case ok
        case degraded(until: Date, lastError: String)
    }

    enum Service: String, CaseIterable {
        case extractor       // YouTubeExtractor local (iPhone → youtube.com)
        case proxy           // yt_proxy.php del VPS
    }

    @Published private(set) var extractor: State = .ok
    @Published private(set) var proxy: State = .ok

    private var extractorFailCount: Int = 0
    private var proxyFailCount: Int = 0

    /// Umbral: N fails consecutivos → open circuit
    private let threshold = 3
    /// Cooldown: cuánto tiempo mantener el circuit abierto
    private let cooldown: TimeInterval = 5 * 60  // 5 min

    private init() {}

    // MARK: - API pública

    /// ¿Podemos usar este servicio ahora?
    func isAvailable(_ s: Service) -> Bool {
        let st = get(s)
        switch st {
        case .ok: return true
        case .degraded(let until, _): return Date() >= until
        }
    }

    /// Reporta éxito — resetea contador de fails.
    func reportSuccess(_ s: Service) {
        set(s, state: .ok)
        switch s {
        case .extractor: extractorFailCount = 0
        case .proxy: proxyFailCount = 0
        }
    }

    /// Reporta fallo. Si superamos threshold, abre el circuit por `cooldown`.
    /// Devuelve true si acaba de abrirse (para mostrar toast).
    @discardableResult
    func reportFailure(_ s: Service, error: String) -> Bool {
        let count: Int
        switch s {
        case .extractor:
            extractorFailCount += 1
            count = extractorFailCount
        case .proxy:
            proxyFailCount += 1
            count = proxyFailCount
        }

        if count >= threshold {
            let until = Date().addingTimeInterval(cooldown)
            set(s, state: .degraded(until: until, lastError: error))
            print("[Health] \(s.rawValue) DEGRADED (\(count) fails) hasta \(until) — \(error)")
            return true
        }
        return false
    }

    /// Fuerza reset (usado desde botón "Retry ahora" en Ajustes).
    func resetAll() {
        extractor = .ok
        proxy = .ok
        extractorFailCount = 0
        proxyFailCount = 0
    }

    /// Descripción legible para UI.
    func summary(_ s: Service) -> String {
        let st = get(s)
        switch st {
        case .ok: return "OK"
        case .degraded(let until, let err):
            let mins = max(1, Int(until.timeIntervalSinceNow / 60))
            return "Bloqueado \(mins)min · \(err)"
        }
    }

    // MARK: - Privado
    private func get(_ s: Service) -> State {
        switch s {
        case .extractor: return extractor
        case .proxy: return proxy
        }
    }
    private func set(_ s: Service, state: State) {
        switch s {
        case .extractor: extractor = state
        case .proxy: proxy = state
        }
    }
}
