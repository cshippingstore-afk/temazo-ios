import SwiftUI

/// Bottom sheet de opciones para una canción (long-press en TrackRow).
struct TrackOptionsSheet: View {
    let track: Track
    let isFavorite: Bool
    var onDismiss: () -> Void
    var onToggleFav: () -> Void
    var onAddToPlaylist: () -> Void
    var onAddToQueue: () -> Void
    var onGoToArtist: () -> Void
    var onGoToAlbum: () -> Void
    var onShare: () -> Void
    var onRecommend: (() -> Void)? = nil

    // BETA v1.2.22: acciones admin/report inline (no callbacks — el sheet abre
    // sus propias sub-sheets). Se apoyan en AdminService.shared que lleva el flag is_admin.
    @ObservedObject private var admin = AdminService.shared
    @State private var showReport = false
    @State private var showAdminReplace = false
    @State private var showAdminEdit = false
    @State private var showAdminHide = false
    // BETA v1.2.24 — Tier 2/3 admin
    @State private var showAdminBoost = false
    @State private var showAdminReassign = false
    @State private var showAdminMerge = false
    @State private var showAdminRehydrate = false
    @State private var showAdminYTSearch = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                CoverImage(url: track.coverUrl, size: 56, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(track.artistName ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.65)).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)

            row(icon: isFavorite ? "heart.fill" : "heart",
                label: isFavorite ? "Quitar de Me gusta" : "Añadir a Me gusta",
                tint: isFavorite ? Color.neonPink : .white) {
                onToggleFav(); onDismiss()
            }
            row(icon: "plus.rectangle.on.rectangle", label: "Añadir a playlist") {
                onAddToPlaylist(); onDismiss()
            }
            row(icon: "text.line.first.and.arrowtriangle.forward", label: "Añadir a la cola") {
                onAddToQueue(); onDismiss()
            }
            // BETA v1 — botón de descarga manual (independiente del corazón)
            downloadRow

            if track.artistId != nil || (track.artistSlug?.isEmpty == false) {
                row(icon: "person.fill", label: "Ir al artista") {
                    onGoToArtist(); onDismiss()
                }
            }
            if track.albumId != nil || (track.albumSlug?.isEmpty == false) {
                row(icon: "square.stack.fill", label: "Ir al álbum") {
                    onGoToAlbum(); onDismiss()
                }
            }
            row(icon: "square.and.arrow.up", label: "Compartir") {
                onShare(); onDismiss()
            }
            if let onRec = onRecommend {
                row(icon: "paperplane", label: "Recomendar a un amigo") {
                    onRec(); onDismiss()
                }
            }

            // BETA v1.2.22 — Reportar problema (todos los users logueados)
            Divider().background(Color.white.opacity(0.08)).padding(.vertical, 4)
            row(icon: "exclamationmark.bubble", label: "Reportar problema", tint: Color.orange) {
                showReport = true
            }

            // Admin-only actions
            if admin.isAdmin {
                Divider().background(Color.white.opacity(0.08)).padding(.vertical, 4)
                row(icon: "arrow.left.arrow.right.circle",
                    label: "Reemplazar video YouTube",
                    tint: Color.cyan) { showAdminReplace = true }
                row(icon: "magnifyingglass.circle",
                    label: "Buscar YT + preview",
                    tint: Color.cyan) { showAdminYTSearch = true }
                row(icon: "square.and.pencil",
                    label: "Editar metadata",
                    tint: Color.cyan) { showAdminEdit = true }
                row(icon: "square.stack.3d.up.badge.a",
                    label: "Reasignar álbum",
                    tint: Color.cyan) { showAdminReassign = true }
                row(icon: "chart.line.uptrend.xyaxis",
                    label: "Boost trending",
                    tint: Color.cyan) { showAdminBoost = true }
                row(icon: "arrow.triangle.merge",
                    label: "Fusionar con otro track",
                    tint: Color.cyan) { showAdminMerge = true }
                row(icon: "arrow.clockwise.circle",
                    label: "Re-hidratar desde YT",
                    tint: Color.orange) { showAdminRehydrate = true }
                row(icon: "eye.slash",
                    label: "Ocultar del catálogo",
                    tint: Color.red) { showAdminHide = true }
            }
            Spacer().frame(height: 12)
        }
        .background(Color(red: 0.10, green: 0.04, blue: 0.18))
        .presentationDetents([.fraction(admin.isAdmin ? 0.75 : 0.60), .large])
        .sheet(isPresented: $showReport) {
            AdminReportSheet(targetType: "track", targetId: Int(track.id),
                             targetTitle: "\(track.title) · \(track.artistName ?? "")")
        }
        .sheet(isPresented: $showAdminReplace) {
            AdminReplaceYouTubeSheet(trackId: Int(track.id),
                trackTitle: "\(track.title) · \(track.artistName ?? "")",
                currentYouTubeId: track.youtubeId)
        }
        .sheet(isPresented: $showAdminEdit) {
            AdminEditMetaSheet(trackId: Int(track.id),
                originalTitle: track.title,
                originalArtist: track.artistName ?? "",
                originalReleaseDate: nil,
                originalCoverURL: track.coverUrl)
        }
        .confirmationDialog("¿Ocultar del catálogo?",
                            isPresented: $showAdminHide, titleVisibility: .visible) {
            Button("Ocultar", role: .destructive) { Task { await hideThisTrack() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(track.title) dejará de aparecer en búsquedas y trending. Reversible desde el panel admin.")
        }
        // BETA v1.2.24 — nuevas sheets Tier 2/3
        .sheet(isPresented: $showAdminBoost) {
            AdminBoostSheet(trackId: Int(track.id),
                trackTitle: "\(track.title) · \(track.artistName ?? "")",
                currentPopularity: track.popularity ?? 0)
        }
        .sheet(isPresented: $showAdminReassign) {
            AdminReassignAlbumSheet(trackId: Int(track.id),
                trackTitle: "\(track.title) · \(track.artistName ?? "")",
                currentAlbumName: track.album)
        }
        .sheet(isPresented: $showAdminMerge) {
            AdminMergeTracksSheet(sourceTrack: track)
        }
        .sheet(isPresented: $showAdminYTSearch) {
            AdminYouTubeSearchSheet(initialQuery: "\(track.title) \(track.artistName ?? "")") { chosenId in
                Task {
                    _ = try? await AdminService.shared.replaceYouTube(
                        trackId: Int(track.id), youtube: chosenId,
                        note: "via search+preview")
                }
            }
        }
        .confirmationDialog("¿Re-hidratar desde YouTube?",
                            isPresented: $showAdminRehydrate, titleVisibility: .visible) {
            Button("Re-hidratar") {
                Task {
                    _ = try? await AdminService.shared.forceRehydrate(
                        targetType: "track", targetId: Int(track.id))
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se ejecutará el pipeline en background. Refresca la app en 1-2 min para ver metadata actualizada.")
        }
    }

    private func hideThisTrack() async {
        let tid = Int(track.id)
        do {
            _ = try await AdminService.shared.toggleHidden(
                targetType: "track", targetId: tid, hidden: true)
            onDismiss()
        } catch {
            print("[Admin] hide track \(tid) failed: \(error)")
        }
    }

    /// BETA v1: fila específica para descargar / borrar descarga.
    /// Estado depende de OfflineLibrary + DownloadManager.
    @ViewBuilder
    private var downloadRow: some View {
        if let yt = track.youtubeId, !yt.isEmpty {
            let isDownloaded = OfflineLibrary.shared.isDownloaded(yt)
            let downloading = DownloadManager.shared.states[yt].map { state -> Bool in
                if case .downloading = state { return true }
                if case .queued = state { return true }
                return false
            } ?? false
            if isDownloaded {
                row(icon: "checkmark.circle.fill",
                    label: "Descargada — quitar",
                    tint: .green) {
                    OfflineLibrary.shared.remove(youtubeId: yt); onDismiss()
                }
            } else if downloading {
                row(icon: "hourglass",
                    label: "Descargando…",
                    tint: .yellow) { onDismiss() }
            } else {
                row(icon: "arrow.down.circle",
                    label: "Descargar canción",
                    tint: .white) {
                    DownloadManager.shared.downloadTrackAutoResolve(track)
                    onDismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func row(icon: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint).frame(width: 24)
                Text(label).font(.system(size: 15)).foregroundStyle(tint)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}
