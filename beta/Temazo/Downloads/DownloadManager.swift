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
    /// BETA v1.2.3: pausa entre INICIOS de descarga (para no saturar googlevideo)
    private var lastDownloadStartAt: Date = .distantPast
    private let downloadMinGap: TimeInterval = 2.0  // 2s entre downloads

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

    private func actuallyStart(track: Track, ytId: String, url: URL) {
        // Chequeo WiFi
        if wifiOnly && !isOnWifi {
            queuedTracks.append((track, ytId))
            states[ytId] = .queued
            print("[DL] \(ytId) esperando WiFi (wifiOnly=true, currentWiFi=false)")
            return
        }
        // BETA v1.2.3: pausa 2s entre INICIOS de descarga para no saturar VPS ni googlevideo
        let elapsed = Date().timeIntervalSince(lastDownloadStartAt)
        if elapsed < downloadMinGap {
            let wait = downloadMinGap - elapsed
            print("[DL] \(ytId) esperando \(String(format: "%.1f", wait))s por rate-limit")
            queuedTracks.insert((track, ytId), at: 0)
            states[ytId] = .queued
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                self?.maybeStartQueued()
            }
            return
        }
        lastDownloadStartAt = Date()
        let task = session.downloadTask(with: url)
        activeTasks[ytId] = task
        pendingMeta[task.taskIdentifier] = (track, ytId)
        states[ytId] = .downloading(progress: 0)
        task.resume()
        print("[DL] START \(ytId) \(track.title)")
    }

    private func maybeStartQueued() {
        while activeTasks.count < maxConcurrent, let (track, ytId) = queuedTracks.first {
            queuedTracks.removeFirst()
            if wifiOnly && !isOnWifi {
                // Aún no hay WiFi, dejamos en cola
                queuedTracks.insert((track, ytId), at: 0)
                return
            }
            // BETA v1.2.3: usamos el proxy directamente — sin llamar extractor local.
            // El proxy re-resuelve googlevideo URL cada vez (con cache 5min server-side),
            // así que si la URL expiró, la próxima llamada tiene URL fresca.
            if let proxyURL = self.buildProxyURL(ytId: ytId) {
                self.actuallyStart(track: track, ytId: ytId, url: proxyURL)
            } else {
                self.states[ytId] = .failed("no proxy url")
            }
        }
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
        // El file en `location` es temporal — hay que moverlo YA a nuestro directorio.
        let taskId = downloadTask.taskIdentifier
        // Copiamos el file de forma síncrona (estamos en la callback de URLSession)
        var savedSize: Int64 = 0
        var savedTo: URL? = nil
        var errorMsg: String? = nil
        // Extraemos meta síncronamente vía DispatchQueue.main (no ideal pero necesario)
        // Usamos DispatchQueue sincrono para no soltar location
        var metaLocal: (track: Track, ytId: String)?
        DispatchQueue.main.sync {
            metaLocal = self.pendingMeta[taskId]
        }
        guard let meta = metaLocal else {
            print("[DL] didFinish sin meta para task \(taskId)")
            return
        }
        let dest = OfflineLibrary.shared.destinationURL(for: meta.ytId)
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
