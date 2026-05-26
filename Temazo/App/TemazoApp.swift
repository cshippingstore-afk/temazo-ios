import SwiftUI
import AVFoundation

@main
struct TemazoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var auth = AuthRepository.shared
    @StateObject private var player = Player.shared
    @StateObject private var favorites = FavoritesRepo.shared
    @StateObject private var settings = SettingsRepo.shared

    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environmentObject(auth)
                .environmentObject(player)
                .environmentObject(favorites)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .task {
                    NowPlayingManager.shared.bind(to: player)
                    await auth.refreshSession()
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Universal Link: alguien abrió un enlace temazo.es y la app
                    // está registrada para esos dominios via apple-app-site-association.
                    if let url = activity.webpageURL {
                        DeepLinkRouter.handle(url: url)
                    }
                }
                .onOpenURL { url in
                    // Custom URL scheme (si en el futuro añadimos temazo://)
                    DeepLinkRouter.handle(url: url)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Configurar AVAudioSession ANTES de cualquier UI / cualquier reproducción
        // (importante: si esto se hace en .task de SwiftUI, hay race con play)
        AudioSessionManager.shared.configure()

        // Cache de imágenes 50MB RAM + 200MB disco — reduce flickering en scrolls.
        ImageCacheSetup.configureOnce()

        // Recibir remote control events (lock screen / BT)
        application.beginReceivingRemoteControlEvents()

        // Crash logger
        NSSetUncaughtExceptionHandler { exception in
            let trace = exception.callStackSymbols.joined(separator: "\n")
            let msg = "Temazo crash:\n\(exception.name.rawValue)\n\(exception.reason ?? "")\n\n\(trace)"
            try? msg.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temazo_crash.txt"),
                           atomically: true, encoding: .utf8)
            print("[TemazoCrash]", msg)
        }
        return true
    }

    // MARK: - APNs token

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationManager.shared.register(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotificationManager.shared.registrationFailed(error: error)
        }
    }
}
