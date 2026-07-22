import Foundation
import Combine

/// Heartbeat que envía `now_playing_ping` al backend cada 30s mientras hay
/// un track sonando. Los seguidores ven en el perfil público lo que el usuario
/// está escuchando (a menos que tenga `hide_now_playing` activado).
@MainActor
final class NowPlayingHeartbeat {
    static let shared = NowPlayingHeartbeat()

    private var task: Task<Void, Never>?
    private var started = false

    private init() {}

    func start() {
        if started { return }
        started = true
        task = Task { [weak self] in
            while !(Task.isCancelled) {
                await self?.tick()
                // Heartbeat 15s — tus seguidores ven "escuchando ahora" casi en tiempo real
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            }
        }
    }

    private func tick() async {
        let st = Player.shared.state
        guard st.isPlaying, let t = st.currentTrack else { return }
        _ = try? await TemazoAPI.shared.nowPlayingPing(trackId: t.id)
    }
}
