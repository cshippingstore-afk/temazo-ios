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
                    AudioSessionManager.shared.configure()
                    NowPlayingManager.shared.bind(to: player)
                    await auth.refreshSession()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
}
