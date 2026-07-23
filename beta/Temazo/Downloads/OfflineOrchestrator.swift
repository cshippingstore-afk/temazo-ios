import Foundation
import Combine
import Network

/// BETA v1.2 — orquestador global del modo offline.
///
/// Responsable de:
///   1. Al login (o al arrancar con sesión existente), si los toggles
///      autoDownloadMyPlaylists / autoDownloadFollowedPlaylists están ON,
///      encola descarga de TODAS las canciones de esas playlists.
///   2. Al recuperar WiFi tras estar offline, re-lanza descargas pendientes
///      Y reintenta las que fallaron.
///   3. Escucha cambios de settings — si el user activa un toggle, dispara
///      sincronización inmediata.
///
/// Se llama una vez desde TemazoApp.task { } y vive todo el ciclo de vida.
@MainActor
final class OfflineOrchestrator: ObservableObject {
    static let shared = OfflineOrchestrator()

    /// Última vez que sincronizamos. Evita loops.
    private var lastFullSync: Date = .distantPast
    /// Cooldown mínimo entre sync completas (evita spam en rearranques).
    private let syncCooldown: TimeInterval = 5 * 60  // 5 min

    /// Tarea de watchdog periódica que reintenta failed cada 60s en WiFi.
    private var watchdogTask: Task<Void, Never>? = nil

    private init() {}

    /// Cablear al arrancar la app (TemazoApp.task).
    func start() {
        print("[OfflineOrch] start")

        // BETA v1.2.6: limpiar failed states de sesiones previas antes de sync
        // (user no ve "6 fallos" viejos, se re-encolan como queued).
        DownloadManager.shared.clearFailedStates()

        // 1. BOOT: dispara sync inmediato en cuanto haya sesión + red viable.
        //    Sin esperar cambios de red — puede que ya estés en WiFi al arrancar.
        Task { @MainActor in
            // Espera hasta 5s a que arranquen auth + net monitor
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
                if AuthRepository.shared.currentUser != nil,
                   DownloadManager.shared.isOnWifi || !DownloadManager.shared.wifiOnly {
                    print("[OfflineOrch] BOOT sync — user + red OK")
                    await self.syncAllNow(force: true)
                    break
                }
            }
        }

        // 2. Observar cambios de red — cuando vuelva WiFi, resync
        Task { @MainActor in
            for await _ in DownloadManager.shared.$isOnWifi.values {
                if DownloadManager.shared.isOnWifi {
                    print("[OfflineOrch] WiFi disponible, reintentando failed + syncAll si toca")
                    DownloadManager.shared.retryFailed()
                    if AuthRepository.shared.currentUser != nil {
                        await maybeSyncAll()
                    }
                }
            }
        }

        // 3. Watchdog: cada 60s, si hay tasks en states=failed o toca sync, dispara.
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60s
                guard let self = self else { return }
                if DownloadManager.shared.isOnWifi
                    || !DownloadManager.shared.wifiOnly {
                    DownloadManager.shared.retryFailed()
                    if AuthRepository.shared.currentUser != nil {
                        await self.maybeSyncAll()
                    }
                }
            }
        }
    }

    /// Se llama cuando el user hace login o cambia de sesión. Fuerza sync sin cooldown.
    func onLogin() {
        Task { @MainActor in
            print("[OfflineOrch] onLogin — sync inmediato (force)")
            await syncAllNow(force: true)
        }
    }

    /// Dispara syncAllNow() si hace más de 5 min desde la última.
    private func maybeSyncAll() async {
        guard Date().timeIntervalSince(lastFullSync) > syncCooldown else { return }
        await syncAllNow(force: false)
    }

    /// Fuerza una sincronización completa: recorre favs + mis playlists + playlists
    /// que sigo y encola descargas según los toggles. Idempotente — no re-descarga
    /// lo que ya está en OfflineLibrary. Con `force=true` ignora el cooldown.
    func syncAllNow(force: Bool = false) async {
        if !force, Date().timeIntervalSince(lastFullSync) < syncCooldown {
            print("[OfflineOrch] skip syncAllNow (cooldown)")
            return
        }
        lastFullSync = Date()
        let settings = SettingsRepo.shared
        print("[OfflineOrch] syncAllNow — favs=\(settings.autoDownloadFavorites) myPls=\(settings.autoDownloadMyPlaylists) followed=\(settings.autoDownloadFollowedPlaylists)")

        var totalEnqueued = 0
        // 1. Favoritos
        if settings.autoDownloadFavorites {
            totalEnqueued += await syncFavorites()
        }
        // 2. Mis playlists (owner)
        if settings.autoDownloadMyPlaylists {
            totalEnqueued += await syncMyPlaylists()
        }
        // 3. Playlists que sigo
        if settings.autoDownloadFollowedPlaylists {
            totalEnqueued += await syncFollowedPlaylists()
        }

        // Toast al arrancar sync bulk — user sabe qué está pasando
        if totalEnqueued > 0 {
            NotificationCenter.default.post(
                name: .temazoShowToast, object: nil,
                userInfo: ["text": "🔄 Sincronizando \(totalEnqueued) canciones offline"])
        }
    }

    @discardableResult
    private func syncFavorites() async -> Int {
        do {
            let resp = try await TemazoAPI.shared.favs()
            let n = DownloadManager.shared.downloadAll(resp.tracks)
            print("[OfflineOrch] favs → encoladas \(n) de \(resp.tracks.count)")
            return n
        } catch {
            print("[OfflineOrch] favs error: \(error)")
            return 0
        }
    }

    @discardableResult
    private func syncMyPlaylists() async -> Int {
        var total = 0
        do {
            let pls = try await TemazoAPI.shared.playlists()
            for p in pls.playlists {
                do {
                    let tracks = try await TemazoAPI.shared.playlistTracks(p.id)
                    let n = DownloadManager.shared.downloadAll(tracks.tracks)
                    print("[OfflineOrch] playlist '\(p.name)' → encoladas \(n)")
                    total += n
                } catch {
                    print("[OfflineOrch] tracks playlist \(p.id) error: \(error)")
                }
            }
        } catch {
            print("[OfflineOrch] mis playlists error: \(error)")
        }
        return total
    }

    @discardableResult
    private func syncFollowedPlaylists() async -> Int {
        var total = 0
        do {
            let resp = try await TemazoAPI.shared.playlistsFollowing()
            for p in resp.playlists {
                do {
                    let pub = try await TemazoAPI.shared.playlistPublic(idOrSlug: String(p.id))
                    let n = DownloadManager.shared.downloadAll(pub.tracks ?? [])
                    print("[OfflineOrch] followed pl '\(p.name)' → encoladas \(n)")
                    total += n
                } catch {
                    print("[OfflineOrch] tracks followed pl \(p.id) error: \(error)")
                }
            }
        } catch {
            print("[OfflineOrch] followed playlists error: \(error)")
        }
        return total
    }

    deinit {
        watchdogTask?.cancel()
    }
}
