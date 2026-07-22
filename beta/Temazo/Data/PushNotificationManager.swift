import UIKit
import UserNotifications

/// Gestor APNs — paridad con `TokenManager.kt` (Android) pero adaptado a iOS.
/// - Pide permiso al user (UNUserNotificationCenter)
/// - Registra el device en APNs
/// - El `AppDelegate` recibe el `deviceToken` y llama a `register(token:)` aquí
/// - Sube el token al backend (`pushTokenSet`)
///
/// IMPORTANTE: para que funcione en TestFlight/AppStore:
///   1. Activar capability "Push Notifications" en Apple Developer App ID es.temazo.app
///   2. Crear APNs Auth Key (.p8) en Apple Developer → Keys
///   3. Configurar el backend con el .p8 (server-side, no app)
///   4. El entitlements `aps-environment` se cambia automáticamente a `production` en Release builds
@MainActor
final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()
    private override init() { super.init() }

    private static let lastTokenKey = "temazo.apns.lastToken"

    /// Llamar al login o al arrancar la app si ya hay sesión.
    /// Pide permiso (si aún no se ha pedido) y registra para remote notifications.
    func requestAuthorizationAndRegister() {
        UNUserNotificationCenter.current().delegate = self
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    print("[Push] Authorization denied")
                }
            } catch {
                print("[Push] Auth error: \(error)")
            }
        }
    }

    /// AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken nos pasa el token raw.
    func register(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let last = UserDefaults.standard.string(forKey: Self.lastTokenKey)
        if last == hex {
            // Mismo token que la última vez — no resincronizar
            return
        }
        UserDefaults.standard.set(hex, forKey: Self.lastTokenKey)
        Task {
            do {
                _ = try await TemazoAPI.shared.pushTokenSet(token: hex, platform: "apns")
                print("[Push] Token registered with backend: \(hex.prefix(12))…")
            } catch {
                print("[Push] Token register failed: \(error)")
                // Si falla, borra el cache para que el siguiente arranque reintente
                UserDefaults.standard.removeObject(forKey: Self.lastTokenKey)
            }
        }
    }

    /// Llamar al logout para invalidar el token en el backend.
    func unregister() {
        guard let last = UserDefaults.standard.string(forKey: Self.lastTokenKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.lastTokenKey)
        Task {
            _ = try? await TemazoAPI.shared.pushTokenDelete(token: last)
        }
    }

    func registrationFailed(error: Error) {
        print("[Push] registration failed: \(error)")
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    /// Notificación recibida con la app en foreground — mostrarla igualmente como banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// User tocó la notificación.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo

        // Soporta keys del payload tipo Android:
        //  - "deeplink" → URL absoluta o ruta para DeepLinkRouter
        //  - "kind" + "target_id" → notif tipada (open user, playlist, etc.)
        if let deepLink = info["deeplink"] as? String {
            let normalized = deepLink.hasPrefix("http")
                ? deepLink
                : "https://temazo.es\(deepLink.hasPrefix("/") ? deepLink : "/\(deepLink)")"
            if let url = URL(string: normalized) {
                DeepLinkRouter.handle(url: url)
            }
        } else if let kind = info["kind"] as? String {
            handleKind(kind, info: info)
        }
        // Recargar notif center en background
        Task { @MainActor in _ = await NotificationsRepo.shared.refresh() }
        completionHandler()
    }

    private func handleKind(_ kind: String, info: [AnyHashable: Any]) {
        switch kind {
        case "follow_user", "user_follow":
            if let uid = info["user_id"] as? Int64 ?? Int64((info["user_id"] as? String) ?? "") {
                NotificationCenter.default.post(
                    name: .temazoOpenUserByUsername,
                    object: nil,
                    userInfo: ["userId": uid]
                )
            }
        case "playlist_follow", "playlist":
            if let pid = info["playlist_id"] as? Int64 ?? Int64((info["playlist_id"] as? String) ?? "") {
                NotificationCenter.default.post(
                    name: .temazoOpenPublicPlaylistById,
                    object: nil,
                    userInfo: ["playlistId": pid]
                )
            }
        default:
            // tipo desconocido: abre el centro de notificaciones
            NotificationCenter.default.post(name: .temazoSwitchToAccountTab, object: nil)
        }
    }
}
