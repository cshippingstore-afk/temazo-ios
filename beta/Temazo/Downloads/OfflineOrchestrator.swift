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
        // Observar cambios de red — cuando vuelva WiFi, resync
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
        // Watchdog: cada 60s, si hay tasks en states=failed, reintenta.
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

    /// Dispara syncAllNow() si hace más de 5 min desde la última.
    private func maybeSyncAll() async {
        guard Date().timeIntervalSince(lastFullSync) > syncCooldown else { return }
        await syncAllNow()
    }

    /// Fuerza una sincronización completa: recorre favs + mis playlists + playlists
    /// que sigo y encola descargas según los toggles. Idempotente — no re-descarga
    /// lo que ya está en OfflineLibrary.
    func syncAllNow() async {
        lastFullSync = Date()
        let settings = SettingsRepo.shared
        print("[OfflineOrch] syncAllNow — favs=\(settings.autoDownloadFavorites) myPls=\(settings.autoDownloadMyPlaylists) followed=\(settings.autoDownloadFollowedPlaylists)")

        // 1. Favoritos
        if settings.autoDownloadFavorites {
            await syncFavorites()
        }
        // 2. Mis playlists (owner)
        if settings.autoDownloadMyPlaylists {
            await syncMyPlaylists()
        }
        // 3. Playlists que sigo
        if settings.autoDownloadFollowedPlaylists {
            await syncFollowedPlaylists()
        }
    }

    private func syncFavorites() async {
        do {
            let resp = try await TemazoAPI.shared.favs()
            let n = DownloadManager.shared.downloadAll(resp.tracks)
            print("[OfflineOrch] favs → encoladas \(n) de \(resp.tracks.count)")
        } catch {
            print("[OfflineOrch] favs error: \(error)")
        }
    }

    private func syncMyPlaylists() async {
        do {
            let pls = try await TemazoAPI.shared.playlists()
            for p in pls.playlists {
                do {
                    let tracks = try await TemazoAPI.shared.playlistTracks(p.id)
                    let n = DownloadManager.shared.downloadAll(tracks.tracks)
                    print("[OfflineOrch] playlist '\(p.name)' → encoladas \(n)")
                } catch {
                    print("[OfflineOrch] tracks playlist \(p.id) error: \(error)")
                }
            }
        } catch {
            print("[OfflineOrch] mis playlists error: \(error)")
        }
    }

    private func syncFollowedPlaylists() async {
        do {
            let resp = try await TemazoAPI.shared.playlistsFollowing()
            for p in resp.playlists {
                do {
                    let pub = try await TemazoAPI.shared.playlistPublic(idOrSlug: String(p.id))
                    let n = DownloadManager.shared.downloadAll(pub.tracks ?? [])
                    print("[OfflineOrch] followed pl '\(p.name)' → encoladas \(n)")
                } catch {
                    print("[OfflineOrch] tracks followed pl \(p.id) error: \(error)")
                }
            }
        } catch {
            print("[OfflineOrch] followed playlists error: \(error)")
        }
    }

    deinit {
        watchdogTask?.cancel()
    }
}
