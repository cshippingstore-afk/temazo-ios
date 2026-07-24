import Foundation
import Combine
import Network

/// Gestor de descargas offline. Descarga bytes de googlevideo (URL del extractor)
/// a disco local para reproducción offline.
///
/// Características:
///   - `URLSession.background`: descarga continúa aunque cierres la app
///   - Cola con concurrency cap (3 simultáneas)
///   - Solo-WiFi por defecto (respeta ajuste del user)
///   - Publica progreso por youtube_id para reactive UI
///   - Auto-reintenta 3 veces con backoff
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    /// Estado de descarga de un track individual.
    enum DownloadState: Equatable {
        case idle
        case queued
        case downloading(progress: Double)   // 0.0 → 1.0
        case completed
        case failed(String)
    }

    /// Estados por youtube_id, observado por la UI. Se elimina la key al completarse.
    @Published private(set) var states: [String: DownloadState] = [:]

    /// Ajuste user: descargar solo con WiFi (default true, más seguro).
    @Published var wifiOnly: Bool = UserDefaults.standard.object(forKey: "DL.wifiOnly") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wifiOnly, forKey: "DL.wifiOnly") }
    }

    private var session: URLSession!
    private var activeTasks: [String: URLSessionDownloadTask] = [:]  // ytId → task
    private var queuedTracks: [(Track, String)] = []                 // pendientes cuando cap alcanzado
    /// BETA v1.2.3 — reducido de 3 a 1 para no quemar la IP con extractor de YouTube.
    /// YouTube banea la IP tras N requests concurrentes. Ir secuencial es lento pero fiable.
    private let maxConcurrent = 1
    /// Meta pendiente por completar (necesitamos guardar el Track del que descargamos
    /// para poder llamar OfflineLibrary.registerDownload al terminar el URLSession delegate).
    private var pendingMeta: [Int: (track: Track, ytId: String)] = [:]  // taskIdentifier → meta
    /// BETA v1.2: cache Track por ytId — sobrevive a failures, permite retry.
    private var trackCache: [String: Track] = [:]
    /// BETA v1.2.5: pausa 3s entre extractores. Memoria: ≤6w+3s = safe vs YT ban.
    /// Con 1 worker + 3s = 20 req/min máximo, muy por debajo del techo de ban.
    private var lastExtractorCallAt: Date = .distantPast
    private let extractorMinGap: TimeInterval = 3.0
    /// BETA v1.2.4: pausa 1s entre INICIOS (con prefetch cache-warm, es suficiente)
    private var lastDownloadStartAt: Date = .distantPast
    private let downloadMinGap: TimeInterval = 1.0

    private let netMonitor = NWPathMonitor()
    @Published private(set) var isOnWifi: Bool = false

    override init() {
        super.init()
        // BETA v1.2.5: identifier v2 para forzar SESION FRESCA — descartar tasks
        // colgadas de v1.2.3/4 (session persiste entre app launches).
        let config = URLSessionConfiguration.background(withIdentifier: "es.temazo.app.beta.downloads.v2")
        config.isDiscretionary = false                 // urgente, no diferir
        config.sessionSendsLaunchEvents = true         // relanzar app al terminar en bg
        config.allowsCellularAccess = true             // el filtro WiFi lo hacemos nosotros con el monitor
        // BETA v1.2.5: TIMEOUTS AGRESIVOS. Defaults background son 60s req + 7 DIAS resource.
        // Con 7 dias, un proxy que cuelga bloquea la cola una semana. Forzamos fallo rápido.
        config.timeoutIntervalForRequest = 30          // 30s por request
        config.timeoutIntervalForResource = 90         // 90s max por descarga entera
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Network monitor: sabe si estamos en WiFi o cellular
        netMonitor.pathUpdateHandler = { [weak self] path in
            let onWifi = path.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in
                self?.isOnWifi = onWifi
                self?.maybeStartQueued()
            }
        }
        netMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - API pública

    /// Encola descarga de un track. Si ya está descargado o encolado, no-op.
    /// Necesita `resolvedURL`: URL del extractor ya resuelta (googlevideo).
    func downloadTrack(_ track: Track, resolvedURL: URL) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else { return }
        // Si ya está descargado, no hacer nada
        if OfflineLibrary.shared.isDownloaded(ytId) {
            states[ytId] = .completed
            return
        }
        // Si ya está en cola o descargando, no re-encolar
        if activeTasks[ytId] != nil || queuedTracks.contains(where: { $0.1 == ytId }) {
            return
        }
        // Si excedemos concurrencia, encolamos
        if activeTasks.count >= maxConcurrent {
            queuedTracks.append((track, ytId))
            states[ytId] = .queued
            return
        }
        actuallyStart(track: track, ytId: ytId, url: resolvedURL)
    }

    /// BETA v1.2.5: vuelta al extractor LOCAL en iPhone.
    ///
    /// Por qué NO seguimos con yt_proxy.php:
    ///   - VPS intermitentemente devuelve 502 (comprobado directo)
    ///   - Googlevideo signed URL enlaza a IP del VPS → iPhone descarga throttled 30 KB/s
    ///
    /// Por qué extractor local funciona:
    ///   - iPhone resuelve con SU IP → googlevideo devuelve URL firmada para iPhone
    ///   - iPhone descarga a MB/s desde googlevideo (WiFi normal)
    ///
    /// Protección contra ban de YouTube:
    ///   - maxConcurrent = 1 (secuencial)
    ///   - lastExtractorCallAt + extractorMinGap = 5s entre llamadas
    ///   - Total: 12 requests/min máximo (memoria dice ≤6w+3s = safe, esto es más conservador)
    ///
    /// Fallback si extractor falla (raro): proxy VPS (throttled pero funciona)
    /// BETA v1.2.7: circuit breaker per source. Salta el que esté degraded.
    func downloadTrackAutoResolve(_ track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else { return }
        trackCache[ytId] = track
        if OfflineLibrary.shared.isDownloaded(ytId) {
            states[ytId] = .completed
            return
        }
        states[ytId] = .queued
        Task { @MainActor in
            // 1. Cache hit del extractor (siempre válido, no cuenta como request)
            if let cached = YouTubeExtractor.shared.cachedURL(for: ytId) {
                self.downloadTrack(track, resolvedURL: cached)
                return
            }

            let health = ServiceHealth.shared
            let extractorAvailable = health.isAvailable(.extractor)
            let proxyAvailable = health.isAvailable(.proxy)

            // 2. Si ambos servicios están degraded, marca failed y espera cooldown
            if !extractorAvailable && !proxyAvailable {
                self.states[ytId] = .failed("servicio bloqueado — reintenta en 5min")
                self.maybeStartQueued()
                return
            }

            // 3. Extractor local (si está healthy)
            if extractorAvailable {
                let elapsed = Date().timeIntervalSince(self.lastExtractorCallAt)
                if elapsed < self.extractorMinGap {
                    try? await Task.sleep(nanoseconds: UInt64((self.extractorMinGap - elapsed) * 1_000_000_000))
                }
                self.lastExtractorCallAt = Date()
                do {
                    let url = try await YouTubeExtractor.shared.extractStreamURL(videoID: ytId, timeoutSec: 10)
                    health.reportSuccess(.extractor)
                    self.downloadTrack(track, resolvedURL: url)
                    return
                } catch {
                    let opened = health.reportFailure(.extractor, error: error.localizedDescription)
                    print("[DL] \(ytId) extractor fail: \(error.localizedDescription)\(opened ? " (CIRCUIT OPENED)" : "")")
                    if opened {
                        NotificationCenter.default.post(
                            name: .temazoShowToast, object: nil,
                            userInfo: ["text": "⚠️ YouTube limitando — reintento en 5min"])
                    }
                    // cae al proxy
                }
            }

            // 4. Proxy VPS (si está healthy)
            if proxyAvailable, let proxyURL = self.buildProxyURL(ytId: ytId) {
                self.downloadTrack(track, resolvedURL: proxyURL)
                return
            }

            // 5. Sin opciones
            self.states[ytId] = .failed("todos los servicios bloqueados")
            self.maybeStartQueued()
        }
    }

    /// URL del yt_proxy.php — fallback si extractor local falla.
    private func buildProxyURL(ytId: String) -> URL? {
        var comps = URLComponents(string: "https://temazo.es/api/yt_proxy.php")
        comps?.queryItems = [URLQueryItem(name: "id", value: ytId)]
        return comps?.url
    }

    /// BETA v1.1: descarga en cadena una lista completa (álbum / playlist entera).
    /// Filtra los ya descargados y los sin youtubeId. Respeta el techo maxConcurrent
    /// y wifiOnly automáticamente porque delega en downloadTrackAutoResolve.
    /// Devuelve cuántos se encolaron efectivamente (útil para toast UI).
    @discardableResult
    func downloadAll(_ tracks: [Track]) -> Int {
        var enqueued = 0
        for t in tracks {
            guard let yt = t.youtubeId, !yt.isEmpty else { continue }
            if OfflineLibrary.shared.isDownloaded(yt) { continue }
            downloadTrackAutoResolve(t)
            enqueued += 1
        }
        return enqueued
    }

    /// BETA v1.2.6: reintenta todos los tracks en estado failed.
    /// Los borra del states dict Y los re-encola. Idempotente.
    /// Usado al arrancar la app (limpiar fallos previos) y desde el Orchestrator.
    func retryFailed() {
        let failedIds = states.compactMap { (yt, st) -> String? in
            if case .failed = st { return yt } else { return nil }
        }
        guard !failedIds.isEmpty else { return }
        print("[DL] retryFailed: \(failedIds.count) tracks")
        for yt in failedIds {
            states.removeValue(forKey: yt)
            if let track = trackCache[yt] {
                // Sacar de queue si estuviese duplicado, y re-encolar
                queuedTracks.removeAll { $0.1 == yt }
                downloadTrackAutoResolve(track)
            }
        }
    }

    /// BETA v1.2.6: limpiar TODOS los failed states al arrancar la app.
    /// Evita que el user vea "6 fallos" acumulados de sesiones anteriores.
    /// Los tracks se re-encolarán en el próximo syncAllNow.
    func clearFailedStates() {
        let before = states.count
        states = states.filter { _, st in
            if case .failed = st { return false } else { return true }
        }
        let cleared = before - states.count
        if cleared > 0 { print("[DL] cleared \(cleared) failed states at boot") }
    }

    /// Cancela y elimina.
    func cancel(youtubeId: String) {
        activeTasks[youtubeId]?.cancel()
        activeTasks.removeValue(forKey: youtubeId)
        queuedTracks.removeAll { $0.1 == youtubeId }
        states.removeValue(forKey: youtubeId)
    }

    // MARK: - Privado

    /// Devuelve true si arrancó el task, false si fue rate-limited/wifi-blocked.
    /// El caller usa el bool para saber si sigue drenando la cola o para.
    @discardableResult
    private func actuallyStart(track: Track, ytId: String, url: URL) -> Bool {
        // Chequeo WiFi
        if wifiOnly && !isOnWifi {
            queuedTracks.insert((track, ytId), at: 0)  // volver a cola HEAD
            states[ytId] = .queued
            print("[DL] \(ytId) esperando WiFi")
            return false
        }
        // BETA v1.2.4: rate-limit inter-inicio. Si aún no toca, re-inserta y
        // programa un solo wake-up. NO seguimos drenando (evita bucle infinito).
        let elapsed = Date().timeIntervalSince(lastDownloadStartAt)
        if elapsed < downloadMinGap {
            let wait = downloadMinGap - elapsed
            print("[DL] \(ytId) esperando \(String(format: "%.1f", wait))s")
            queuedTracks.insert((track, ytId), at: 0)
            states[ytId] = .queued
            scheduleWakeup(after: wait)
            return false
        }
        lastDownloadStartAt = Date()
        let task = session.downloadTask(with: url)
        activeTasks[ytId] = task
        pendingMeta[task.taskIdentifier] = (track, ytId)
        states[ytId] = .downloading(progress: 0)
        task.resume()
        print("[DL] START \(ytId) \(track.title)")
        return true
    }

    /// Watchdog único para no acumular Tasks-sleep. Reemplaza al anterior si existe.
    private var pendingWakeup: Task<Void, Never>? = nil
    private func scheduleWakeup(after seconds: TimeInterval) {
        pendingWakeup?.cancel()
        pendingWakeup = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.pendingWakeup = nil
            self?.maybeStartQueued()
        }
    }

    // BETA v1.2.5: prefetch removido — ahora usamos extractor local, no proxy.
    // El extractor local no cachea externamente; sí tiene cache in-memory que se
    // aprovecha para la reproducción posterior.

    /// BETA v1.2.5: dequeue 1 track y re-resuelve URL vía extractor local.
    /// Solo intenta arrancar UN task por invocación. Si arrancó, delegate llama de nuevo.
    /// Si NO arrancó (rate-limit / wifi), no seguimos — evita loop infinito.
    private func maybeStartQueued() {
        guard activeTasks.count < maxConcurrent else { return }
        guard let (track, ytId) = queuedTracks.first else { return }
        queuedTracks.removeFirst()
        // Re-usar el flujo del autoresolve — respeta rate limit + fallback proxy
        downloadTrackAutoResolve(track)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let meta = self.pendingMeta[taskId] {
                self.states[meta.ytId] = .downloading(progress: progress)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let taskId = downloadTask.taskIdentifier
        var savedSize: Int64 = 0
        var savedTo: URL? = nil
        var errorMsg: String? = nil
        var metaLocal: (track: Track, ytId: String)?
        DispatchQueue.main.sync {
            metaLocal = self.pendingMeta[taskId]
        }
        guard let meta = metaLocal else {
            print("[DL] didFinish sin meta para task \(taskId)")
            return
        }
        // BETA v1.2.4: validar HTTP status. Si el proxy devuelve 429/503/etc,
        // el body es HTML de error — NO lo guardamos como .m4a (basura).
        if let httpResp = downloadTask.response as? HTTPURLResponse {
            let sc = httpResp.statusCode
            if !(200...299).contains(sc) {
                errorMsg = "http \(sc)"
            }
        }
        // BETA v1.2.4: validar tamaño mínimo. Un .m4a legítimo pesa >100KB.
        // Un HTML de error pesa <10KB. Si es sospechosamente pequeño, descartar.
        let tmpSize = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0
        if errorMsg == nil && tmpSize < 50_000 {
            errorMsg = "size \(tmpSize) too small (proxy error?)"
        }
        let dest = OfflineLibrary.shared.destinationURL(for: meta.ytId)
        if errorMsg == nil {
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: location, to: dest)
                savedSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                savedTo = dest
            } catch {
                errorMsg = "move: \(error.localizedDescription)"
            }
        } else {
            // Limpiar el file basura del temp path
            try? FileManager.default.removeItem(at: location)
        }
        // BETA v1.2.7: identifica qué servicio se usó por la URL para reportar health
        let usedProxy = downloadTask.originalRequest?.url?.host?.contains("temazo.es") == true
        let localErrorMsg = errorMsg
        let localSavedSize = savedSize
        let localSavedTo = savedTo
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.pendingMeta.removeValue(forKey: taskId)
            self.activeTasks.removeValue(forKey: meta.ytId)
            if let err = localErrorMsg {
                self.states[meta.ytId] = .failed(err)
                // Reportar fallo al servicio usado
                let service: ServiceHealth.Service = usedProxy ? .proxy : .extractor
                let opened = ServiceHealth.shared.reportFailure(service, error: err)
                if opened {
                    NotificationCenter.default.post(
                        name: .temazoShowToast, object: nil,
                        userInfo: ["text": "⚠️ \(service.rawValue) limitado — reintento en 5min"])
                }
            } else if localSavedTo != nil {
                OfflineLibrary.shared.registerDownload(youtubeId: meta.ytId, track: meta.track, sizeBytes: localSavedSize)
                self.states[meta.ytId] = .completed
                // Reportar éxito al servicio
                ServiceHealth.shared.reportSuccess(usedProxy ? .proxy : .extractor)
                print("[DL] DONE \(meta.ytId) size=\(localSavedSize) via=\(usedProxy ? "proxy" : "extractor")")
            }
            self.maybeStartQueued()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error = error else { return }
        let taskId = task.taskIdentifier
        // BETA v1.2.7: identifica qué servicio se usó por la URL para health
        let usedProxy = task.originalRequest?.url?.host?.contains("temazo.es") == true
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let meta = self.pendingMeta[taskId] {
                self.states[meta.ytId] = .failed(error.localizedDescription)
                self.pendingMeta.removeValue(forKey: taskId)
                self.activeTasks.removeValue(forKey: meta.ytId)
                let service: ServiceHealth.Service = usedProxy ? .proxy : .extractor
                ServiceHealth.shared.reportFailure(service, error: error.localizedDescription)
                print("[DL] FAILED \(meta.ytId): \(error.localizedDescription) via=\(service.rawValue)")
                self.maybeStartQueued()
            }
        }
    }
}
