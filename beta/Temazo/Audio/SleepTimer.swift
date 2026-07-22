import Foundation
import Combine

/// Timer global de sleep. Call start(minutes:) para programar la pausa del Player.
/// remainingSec se actualiza cada segundo mientras está activo.
@MainActor
final class SleepTimer: ObservableObject {
    static let shared = SleepTimer()

    @Published private(set) var remainingSec: Int = 0
    @Published private(set) var isActive: Bool = false

    private var task: Task<Void, Never>?

    private init() {}

    func start(minutes: Int) {
        cancel()
        let total = max(1, minutes) * 60
        remainingSec = total
        isActive = true
        task = Task { [weak self] in
            while !(Task.isCancelled) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if !self.isActive { return }
                self.remainingSec -= 1
                if self.remainingSec <= 0 {
                    self.isActive = false
                    Player.shared.pause()
                    return
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isActive = false
        remainingSec = 0
    }
}
