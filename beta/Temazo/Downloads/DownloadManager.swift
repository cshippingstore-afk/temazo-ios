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
    /// BETA v1.2.3: pausa entre llamadas al extractor para no ser baneados.
    private var lastExtractorCallAt: Date = .distantPast
    private let extractorMinGap: TimeInterval = 3.0  // 3s entre calls
    /// BETA v1.2.4: pausa 1s entre INICIOS (con prefetch cache-warm, es suficiente)
    private var lastDownloadStartAt: Date = .distantPast
    private let downloadMinGap: TimeInterval = 1.0

    private let netMonitor = NWPathMonitor()
    @Published private(set) var isOnWifi: Bool = false

    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "es.temazo.app.beta.downloads")
        config.isDiscretionary = false                 // urgente, no diferir
        config.sessionSendsLaunchEvents = true         // relanzar app al terminar en bg
        config.allowsCellularAccess = true             // el filtro WiFi lo hacemos nosotros con el monitor
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

    /// BETA v1.2.3: descarga TODO via yt_proxy.php del VPS. El iPhone NUNCA habla
    /// con YouTube. Por qué:
    ///   - Extractor local usa la IP del iPhone → 58 requests seguidos → ban de YouTube
    ///   - yt_proxy.php usa yt-dlp en el VPS (una única IP tuya, ya "conocida")
    ///     y devuelve un 302 hacia googlevideo.com — googlevideo NO banea (solo www.youtube.com sí)
    ///   - El .m4a viene DIRECTO de googlevideo (no consume ancho de banda del VPS)
    ///
    /// Resultado: imposible que YouTube banee al user; el único que hace requests
    /// de extracción es tu VPS (una IP), rate-limitado y cacheado a nivel server.
    func downloadTrackAutoResolve(_ track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else { return }
        trackCache[ytId] = track
        if OfflineLibrary.shared.isDownloaded(ytId) {
            states[ytId] = .completed
            return
        }
        states[ytId] = .queued
        // URL directa al proxy — el propio yt_proxy.php responde con 302 al googlevideo real
        guard let proxyURL = self.buildProxyURL(ytId: ytId) else {
            states[ytId] = .failed("no proxy url")
            return
        }
        downloadTrack(track, resolvedURL: proxyURL)
    }

    /// URL del yt_proxy.php — resolución + 302 al googlevideo server-side.
    private func buildProxyURL(ytId: String) -> URL? {
        var comps = URLComponents(string: "https://temazo.es/api/yt_proxy.php")
        comps?.queryItems = [
            URLQueryItem(name: "id", value: ytId),
            URLQueryItem(name: "format", value: "audio")  // hint al proxy: solo m4a
        ]
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

    /// BETA v1.2: reintenta todos los tracks en estado failed usando trackCache.
    /// Idempotente — safe llamar múltiples veces.
    func retryFailed() {
        let failedIds = states.compactMap { (yt, st) -> String? in
            if case .failed = st { return yt } else { return nil }
        }
        guard !failedIds.isEmpty else { return }
        print("[DL] retryFailed: \(failedIds.count) tracks")
        for yt in failedIds {
            states.removeValue(forKey: yt)
            if let track = trackCache[yt] {
                downloadTrackAutoResolve(track)
            }
        }
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
        // BETA v1.2.4: prefetch — pre-calienta el cache del proxy para las próximas 2
        // canciones. HEAD request es liviano y el proxy cachea 5min. Cuando toque
        // realmente descargarlas, el 302 es casi instantáneo (sin re-resolver yt-dlp).
        prefetchNextProxyURLs(count: 2)
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

    /// BETA v1.2.4: prefetch cache del proxy para las próximas N canciones en cola.
    /// Un HEAD request es minimal (headers only) pero hace que yt_proxy.php resuelva
    /// yt-dlp y guarde el 302 en su cache 5min. Cuando toque descargar en serio,
    /// el proxy devuelve 302 instant (sin gastar tiempo re-resolviendo).
    private func prefetchNextProxyURLs(count: Int) {
        let upcoming = queuedTracks.prefix(count).compactMap { $0.0.youtubeId }
        for ytId in upcoming {
            guard let url = buildProxyURL(ytId: ytId) else { continue }
            Task.detached(priority: .background) {
                var req = URLRequest(url: url)
                req.httpMethod = "HEAD"
                req.timeoutInterval = 5
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }

    /// BETA v1.2.4: sólo intenta arrancar UN task por invocación. Si arrancó,
    /// el propio ciclo (delegate on finish) llama de nuevo. Si NO arrancó
    /// (rate-limit / wifi), no seguimos drenando — evita loop infinito.
    private func maybeStartQueued() {
        guard activeTasks.count < maxConcurrent else { return }
        guard let (track, ytId) = queuedTracks.first else { return }
        queuedTracks.removeFirst()
        guard let proxyURL = buildProxyURL(ytId: ytId) else {
            states[ytId] = .failed("no proxy url")
            // Continúa con la siguiente
            maybeStartQueued()
            return
        }
        // actuallyStart devuelve true si arrancó, false si re-encoló
        _ = actuallyStart(track: track, ytId: ytId, url: proxyURL)
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
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.pendingMeta.removeValue(forKey: taskId)
            self.activeTasks.removeValue(forKey: meta.ytId)
            if let err = errorMsg {
                self.states[meta.ytId] = .failed(err)
            } else if savedTo != nil {
                OfflineLibrary.shared.registerDownload(youtubeId: meta.ytId, track: meta.track, sizeBytes: savedSize)
                self.states[meta.ytId] = .completed
                print("[DL] DONE \(meta.ytId) size=\(savedSize)")
            }
            self.maybeStartQueued()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error = error else { return }
        let taskId = task.taskIdentifier
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let meta = self.pendingMeta[taskId] {
                self.states[meta.ytId] = .failed(error.localizedDescription)
                self.pendingMeta.removeValue(forKey: taskId)
                self.activeTasks.removeValue(forKey: meta.ytId)
                print("[DL] FAILED \(meta.ytId): \(error.localizedDescription)")
                self.maybeStartQueued()
            }
        }
    }
}
