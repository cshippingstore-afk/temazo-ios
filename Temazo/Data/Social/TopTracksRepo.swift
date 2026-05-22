import Foundation
import Combine

/// Mantiene en memoria el conjunto de track_ids que están en el Top 100 de Apple
/// Music de cualquier país hispanohablante. Refresca cada 5 min en background.
/// Lo consultan los reproductores (mini + full) para pintar el "brazalete TOP" en
/// el cover automáticamente si la canción actual está en algún top, sin importar
/// desde qué pantalla se haya reproducido.
@MainActor
final class TopTracksRepo: ObservableObject {
    static let shared = TopTracksRepo()
    @Published private(set) var ids: Set<Int64> = []

    private var started = false
    private var task: Task<Void, Never>?

    private init() {}

    func start() {
        if started { return }
        started = true
        task = Task { [weak self] in
            while !(Task.isCancelled) {
                let ok = await self?.refresh() ?? false
                // Retry rápido cada 30s si la primera carga falla (sin red, etc.).
                // Cuando hay datos, refresh tranquilo cada 5 min.
                let delay: UInt64 = ok ? 5 * 60 * 1_000_000_000 : 30 * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        do {
            let r = try await TemazoAPI.shared.topTrackIds()
            self.ids = Set(r.ids)
            return true
        } catch {
            return false
        }
    }

    func isInTop(_ trackId: Int64?) -> Bool {
        guard let id = trackId else { return false }
        return ids.contains(id)
    }
}
