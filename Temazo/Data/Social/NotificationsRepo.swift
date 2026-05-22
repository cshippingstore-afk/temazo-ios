import Foundation
import Combine
import UIKit

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
                // Polling 5s — la campana se actualiza casi instantánea.
                // Carga ligera (sólo cuenta de unread + últimas 50 notifs).
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }

        // Refresh inmediato cuando la app vuelve al foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in _ = await self?.refresh() }
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
