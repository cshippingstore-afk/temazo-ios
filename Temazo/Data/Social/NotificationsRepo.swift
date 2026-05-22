import Foundation
import Combine

/// Polling de notificaciones in-app del usuario logueado.
/// El TopBar muestra una campana con el badge `unread`.
@MainActor
final class NotificationsRepo: ObservableObject {
    static let shared = NotificationsRepo()

    @Published private(set) var notifications: [TemazoNotification] = []
    @Published private(set) var unread: Int = 0

    private var started = false
    private var task: Task<Void, Never>?

    private init() {}

    func start() {
        if started { return }
        started = true
        task = Task { [weak self] in
            while !(Task.isCancelled) {
                _ = await self?.refresh()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil; started = false
    }

    @discardableResult
    func refresh() async -> Bool {
        do {
            let r = try await TemazoAPI.shared.notifications(limit: 50)
            self.notifications = r.notifications
            self.unread = r.unread
            return true
        } catch {
            return false
        }
    }

    func markAllRead() async {
        _ = try? await TemazoAPI.shared.notifMarkAllRead()
        unread = 0
        notifications = notifications.map { n in
            // Mark as read locally: créate one con read_at distinto a nil via JSON roundtrip
            n
        }
        await refresh()
    }
}
