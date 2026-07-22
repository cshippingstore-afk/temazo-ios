import Foundation
import Combine

/// Settings repo (UserDefaults). Equivalente de SettingsRepo.kt.
@MainActor
final class SettingsRepo: ObservableObject {
    static let shared = SettingsRepo()
    private let kCrossfadeOn = "crossfade_enabled"
    private let kCrossfadeSec = "crossfade_seconds"

    @Published var crossfadeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(crossfadeEnabled, forKey: kCrossfadeOn)
            applyToPlayer()
        }
    }
    @Published var crossfadeSeconds: Int {
        didSet {
            let v = max(0, min(6, crossfadeSeconds))
            UserDefaults.standard.set(v, forKey: kCrossfadeSec)
            if v != crossfadeSeconds { crossfadeSeconds = v; return }
            applyToPlayer()
        }
    }

    private init() {
        crossfadeEnabled = UserDefaults.standard.bool(forKey: kCrossfadeOn)
        let s = UserDefaults.standard.integer(forKey: kCrossfadeSec)
        crossfadeSeconds = s == 0 ? 2 : s
    }

    private func applyToPlayer() {
        let ms = crossfadeEnabled ? crossfadeSeconds * 1000 : 250
        Player.shared.setCrossfadeMs(ms)
    }
}
