import SwiftUI

/// Pantalla "Descargas": lista de todas las canciones que el user ha descargado.
/// Accesible desde el menú principal (bottom nav o sidebar).
struct DownloadsScreen: View {
    @StateObject private var lib = OfflineLibrary.shared
    @StateObject private var dl = DownloadManager.shared
    @EnvironmentObject var player: Player
    @State private var showRemoveAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if lib.tracks.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Descargas")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(.textLow)
            }
            Spacer()
            if !lib.tracks.isEmpty {
                Menu {
                    Button("Actualizar antiguas (>90 días)") {
                        refreshOld()
                    }
                    .disabled(lib.tracksNeedingRefresh.isEmpty)
                    Button("Borrar todas", role: .destructive) {
                        showRemoveAllConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.bgSurface.opacity(0.5))
        .confirmationDialog("¿Borrar todas las descargas?", isPresented: $showRemoveAllConfirm) {
            Button("Borrar todo (\(lib.tracks.count) canciones)", role: .destructive) {
                lib.removeAll()
            }
            Button("Cancelar", role: .cancel) { }
        }
    }

    private var subtitleText: String {
        let mb = Double(lib.totalBytes()) / 1_048_576
        let str = mb >= 1000 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
        let refreshCount = lib.tracksNeedingRefresh.count
        if refreshCount > 0 {
            return "\(lib.tracks.count) canciones · \(str) · \(refreshCount) por refrescar"
        }
        return "\(lib.tracks.count) canciones · \(str)"
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundStyle(.textLow)
            Text("Sin descargas")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Toca la flecha ↓ en cualquier canción para descargarla y escuchar sin conexión.")
                .font(.system(size: 14))
                .foregroundStyle(.textLow)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(lib.tracks) { entry in
                    DownloadedRow(entry: entry) {
                        playTrack(from: entry)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 100)  // player bar space
        }
    }

    private func playTrack(from entry: OfflineLibrary.Entry) {
        // Reconstruir un Track a partir del metadata almacenado
        let track = Track(
            id: Int(entry.track_id),
            title: entry.title,
            slug: nil,
            youtube_id: entry.youtube_id,
            spotify_id: nil,
            artist_id: nil,
            artist_name: entry.artist_name,
            album: entry.album,
            album_id: nil,
            album_slug: nil,
            cover_medium: entry.cover_url,
            cover_large: entry.cover_url,
            duration_sec: entry.duration_sec
        )
        // Cola = todos los descargados en orden
        let queue = lib.tracks.map { e in
            Track(
                id: Int(e.track_id), title: e.title, slug: nil,
                youtube_id: e.youtube_id, spotify_id: nil,
                artist_id: nil, artist_name: e.artist_name,
                album: e.album, album_id: nil, album_slug: nil,
                cover_medium: e.cover_url, cover_large: e.cover_url,
                duration_sec: e.duration_sec
            )
        }
        let idx = queue.firstIndex(where: { $0.youtubeId == entry.youtube_id }) ?? 0
        player.playTrack(track, queue: queue, index: idx, source: "downloads")
    }

    private func refreshOld() {
        for entry in lib.tracksNeedingRefresh {
            // Re-download: borra el archivo actual y lo vuelve a bajar
            // (auto-encolamos el download)
            lib.remove(youtubeId: entry.youtube_id)
            let track = Track(
                id: Int(entry.track_id), title: entry.title, slug: nil,
                youtube_id: entry.youtube_id, spotify_id: nil,
                artist_id: nil, artist_name: entry.artist_name,
                album: entry.album, album_id: nil, album_slug: nil,
                cover_medium: entry.cover_url, cover_large: entry.cover_url,
                duration_sec: entry.duration_sec
            )
            dl.downloadTrackAutoResolve(track)
        }
    }
}

// MARK: - Row individual con info del entry descargado

private struct DownloadedRow: View {
    let entry: OfflineLibrary.Entry
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CoverImage(url: entry.cover_url, size: 44, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.artist_name)
                    .font(.system(size: 12))
                    .foregroundStyle(.textLow)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(sizeString)
                    .font(.system(size: 10))
                    .foregroundStyle(.textLow)
                if entry.refresh_needed {
                    Text("Refrescar")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.bgSurface)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var sizeString: String {
        let mb = Double(entry.file_size_bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }
}
