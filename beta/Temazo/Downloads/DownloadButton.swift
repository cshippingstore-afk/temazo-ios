import SwiftUI

/// Botón de descarga para usar en TrackRow, AlbumScreen, etc.
///
/// Estados visuales:
///   - Idle (no descargado): flecha ↓ gris. Tap → inicia descarga
///   - Queued: reloj de arena. Tap → cancela
///   - Downloading: círculo de progreso animado con %. Tap → cancela
///   - Completed: check verde ✓. Tap → confirmación borrar
///   - Failed: X roja con tooltip error. Tap → reintenta
struct DownloadButton: View {
    let track: Track
    var size: CGFloat = 20

    @StateObject private var dl = DownloadManager.shared
    @StateObject private var lib = OfflineLibrary.shared
    @State private var showRemoveConfirm = false

    private var youtubeId: String? { track.youtubeId }

    private var state: DownloadManager.DownloadState {
        guard let yt = youtubeId else { return .idle }
        if lib.isDownloaded(yt) { return .completed }
        return dl.states[yt] ?? .idle
    }

    var body: some View {
        Group {
            switch state {
            case .idle:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.gray)
                    .onTapGesture { start() }
            case .queued:
                Image(systemName: "hourglass")
                    .foregroundStyle(.yellow)
                    .onTapGesture { cancel() }
            case .downloading(let progress):
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: progress)
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .onTapGesture { cancel() }
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .onTapGesture { showRemoveConfirm = true }
            case .failed(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .onTapGesture { start() }
                    .help(msg)
            }
        }
        .font(.system(size: size))
        .frame(width: size + 8, height: size + 8)
        .confirmationDialog("¿Eliminar descarga?", isPresented: $showRemoveConfirm) {
            Button("Eliminar", role: .destructive) {
                if let yt = youtubeId { lib.remove(youtubeId: yt) }
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("La canción seguirá disponible en streaming.")
        }
    }

    private func start() {
        dl.downloadTrackAutoResolve(track)
    }
    private func cancel() {
        guard let yt = youtubeId else { return }
        dl.cancel(youtubeId: yt)
    }
}
