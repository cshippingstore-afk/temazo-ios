import Foundation
import Combine

/// Librería offline persistente — mantiene metadatos de todas las canciones descargadas.
///
/// Almacenamiento:
///   Documents/
///   ├── downloads/<youtube_id>.m4a  ← los bytes de audio
///   └── offline_library.json         ← este metadata store
///
/// Todo el estado es serializable a JSON simple (sin dependencias externas).
/// `@Published tracks` para que la UI reaccione automáticamente a cambios.
@MainActor
final class OfflineLibrary: ObservableObject {
    static let shared = OfflineLibrary()

    struct Entry: Codable, Identifiable, Equatable {
        var youtube_id: String
        var track_id: Int64
        var title: String
        var artist_name: String
        var album: String?
        var cover_url: String?
        var duration_sec: Int?
        var downloaded_at: Date
        var file_size_bytes: Int64
        /// v1.0.0: refresh manual 90 días después de descarga.
        /// UI muestra badge naranja si `Date() > downloaded_at + 90 días`.
        var refresh_needed: Bool { Date().timeIntervalSince(downloaded_at) > 90 * 24 * 3600 }
        var id: String { youtube_id }
    }

    @Published private(set) var tracks: [Entry] = []
    private let metadataURL: URL
    private let downloadsDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.downloadsDir = docs.appendingPathComponent("downloads", isDirectory: true)
        self.metadataURL = docs.appendingPathComponent("offline_library.json")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        loadFromDisk()
        pruneOrphans()
    }

    // MARK: - Lectura

    /// URL local del archivo si existe. Nil si no está descargado.
    func localURL(for youtubeId: String) -> URL? {
        let file = downloadsDir.appendingPathComponent("\(youtubeId).m4a")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    func isDownloaded(_ youtubeId: String) -> Bool {
        localURL(for: youtubeId) != nil
    }

    func entry(for youtubeId: String) -> Entry? {
        tracks.first { $0.youtube_id == youtubeId }
    }

    func totalBytes() -> Int64 {
        tracks.reduce(0) { $0 + $1.file_size_bytes }
    }

    func totalCount() -> Int { tracks.count }

    /// URL de destino donde el DownloadManager debe escribir el archivo m4a.
    /// El directorio se crea si no existe.
    func destinationURL(for youtubeId: String) -> URL {
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        return downloadsDir.appendingPathComponent("\(youtubeId).m4a")
    }

    // MARK: - Escritura

    /// Registrar un nuevo track descargado. Reemplaza si ya existía.
    func registerDownload(youtubeId: String, track: Track, sizeBytes: Int64) {
        let entry = Entry(
            youtube_id: youtubeId,
            track_id: Int64(track.id),
            title: track.title,
            artist_name: track.artistName ?? "",
            album: track.album,
            cover_url: track.coverUrl,
            duration_sec: track.durationSec,
            downloaded_at: Date(),
            file_size_bytes: sizeBytes
        )
        tracks.removeAll { $0.youtube_id == youtubeId }
        tracks.append(entry)
        tracks.sort { $0.downloaded_at > $1.downloaded_at }
        saveToDisk()
    }

    /// Elimina un track (archivo m4a + entrada metadata).
    func remove(youtubeId: String) {
        let file = downloadsDir.appendingPathComponent("\(youtubeId).m4a")
        try? FileManager.default.removeItem(at: file)
        tracks.removeAll { $0.youtube_id == youtubeId }
        saveToDisk()
    }

    /// Borra TODAS las descargas (archivos + metadata). Confirmar en UI antes.
    func removeAll() {
        for entry in tracks {
            let file = downloadsDir.appendingPathComponent("\(entry.youtube_id).m4a")
            try? FileManager.default.removeItem(at: file)
        }
        tracks.removeAll()
        saveToDisk()
    }

    // MARK: - Refresh 90d

    /// Tracks que necesitan re-descarga (>90 días).
    var tracksNeedingRefresh: [Entry] {
        tracks.filter { $0.refresh_needed }
    }

    // MARK: - Persistencia disco

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: metadataURL) else {
            print("[OfflineLib] sin metadata previa (primera ejecución)")
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([Entry].self, from: data)
            self.tracks = loaded.sorted { $0.downloaded_at > $1.downloaded_at }
            print("[OfflineLib] cargados \(loaded.count) tracks del disco")
        } catch {
            print("[OfflineLib] error decoding: \(error)")
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(tracks)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("[OfflineLib] error saving: \(error)")
        }
    }

    /// Elimina metadata de archivos que ya no existen físicamente (por ejemplo
    /// si iOS purgó Documents por falta de espacio — raro pero posible).
    private func pruneOrphans() {
        let before = tracks.count
        tracks.removeAll { entry in
            let file = downloadsDir.appendingPathComponent("\(entry.youtube_id).m4a")
            return !FileManager.default.fileExists(atPath: file.path)
        }
        if tracks.count != before {
            print("[OfflineLib] pruned \(before - tracks.count) orphan entries")
            saveToDisk()
        }
    }
}
