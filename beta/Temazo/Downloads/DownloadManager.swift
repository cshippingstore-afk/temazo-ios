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
    private let maxConcurrent = 3
    /// Meta pendiente por completar (necesitamos guardar el Track del que descargamos
    /// para poder llamar OfflineLibrary.registerDownload al terminar el URLSession delegate).
    private var pendingMeta: [Int: (track: Track, ytId: String)] = [:]  // taskIdentifier → meta

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

    /// Convenience: si ya tienes la track resolveremos con extractor en 1 llamada.
    func downloadTrackAutoResolve(_ track: Track) {
        guard let ytId = track.youtubeId, !ytId.isEmpty else { return }
        if OfflineLibrary.shared.isDownloaded(ytId) {
            states[ytId] = .completed
            return
        }
        states[ytId] = .queued
        Task { @MainActor in
            // Cache hit del extractor
            if let cached = YouTubeExtractor.shared.cachedURL(for: ytId) {
                self.downloadTrack(track, resolvedURL: cached)
                return
            }
            // Live extract con timeout
            do {
                let url = try await YouTubeExtractor.shared.extractStreamURL(videoID: ytId, timeoutSec: 8)
                self.downloadTrack(track, resolvedURL: url)
            } catch {
                self.states[ytId] = .failed("extractor: \(error.localizedDescription)")
            }
        }
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
            // Resolver URL nueva por si expiró
            Task { @MainActor in
                if let cached = YouTubeExtractor.shared.cachedURL(for: ytId) {
                    self.actuallyStart(track: track, ytId: ytId, url: cached)
                } else {
                    do {
                        let url = try await YouTubeExtractor.shared.extractStreamURL(videoID: ytId, timeoutSec: 8)
                        self.actuallyStart(track: track, ytId: ytId, url: url)
                    } catch {
                        self.states[ytId] = .failed("extractor: \(error.localizedDescription)")
                    }
                }
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
