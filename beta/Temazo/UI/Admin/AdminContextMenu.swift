import SwiftUI

/// Modificador que añade acciones admin/report a cualquier card (track/artist/album).
/// Uso:
///     TrackCard(...)
///         .adminActions(track: track)
///     ArtistCard(...)
///         .adminActions(artist: artist)
///
/// Los botones de admin solo se pintan si el user actual es owner (AdminService.isAdmin).
/// El botón "Reportar" siempre está disponible para users logueados.
struct AdminActionsModifier: ViewModifier {
    enum Target {
        case track(id: Int, title: String, artistName: String, youtubeId: String?,
                   releaseDate: String?, coverURL: String?)
        case artist(id: Int, name: String)
        case album(id: Int, name: String, artistName: String)

        var typeString: String {
            switch self {
            case .track:  return "track"
            case .artist: return "artist"
            case .album:  return "album"
            }
        }
        var id: Int {
            switch self {
            case .track(let id, _, _, _, _, _): return id
            case .artist(let id, _):            return id
            case .album(let id, _, _):          return id
            }
        }
        var displayTitle: String {
            switch self {
            case .track(_, let t, let a, _, _, _): return "\(t) · \(a)"
            case .artist(_, let n):                return n
            case .album(_, let n, let a):          return "\(n) · \(a)"
            }
        }
    }

    let target: Target
    var onChanged: (() -> Void)? = nil

    @ObservedObject private var admin = AdminService.shared
    @State private var showReport = false
    @State private var showReplaceYT = false
    @State private var showEditMeta = false
    @State private var showHideConfirm = false
    @State private var lastError: String? = nil

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    showReport = true
                } label: {
                    Label("Reportar problema", systemImage: "exclamationmark.bubble")
                }

                if admin.isAdmin {
                    Divider()
                    Section("Admin") {
                        if case .track(_, _, _, _, _, _) = target {
                            Button {
                                showReplaceYT = true
                            } label: {
                                Label("Reemplazar video YouTube", systemImage: "arrow.left.arrow.right.circle")
                            }
                            Button {
                                showEditMeta = true
                            } label: {
                                Label("Editar metadata", systemImage: "square.and.pencil")
                            }
                        }
                        Button(role: .destructive) {
                            showHideConfirm = true
                        } label: {
                            Label("Ocultar del catálogo", systemImage: "eye.slash")
                        }
                    }
                }
            }
            .sheet(isPresented: $showReport) {
                AdminReportSheet(targetType: target.typeString,
                                 targetId: target.id,
                                 targetTitle: target.displayTitle)
            }
            .sheet(isPresented: $showReplaceYT) {
                if case let .track(id, title, artist, ytId, _, _) = target {
                    AdminReplaceYouTubeSheet(trackId: id,
                                             trackTitle: "\(title) · \(artist)",
                                             currentYouTubeId: ytId,
                                             onSaved: { _ in onChanged?() })
                }
            }
            .sheet(isPresented: $showEditMeta) {
                if case let .track(id, title, artist, _, rd, cover) = target {
                    AdminEditMetaSheet(trackId: id,
                                       originalTitle: title,
                                       originalArtist: artist,
                                       originalReleaseDate: rd,
                                       originalCoverURL: cover,
                                       onSaved: { onChanged?() })
                }
            }
            .confirmationDialog("¿Ocultar del catálogo?",
                                isPresented: $showHideConfirm, titleVisibility: .visible) {
                Button("Ocultar", role: .destructive) {
                    Task { await hide() }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("\(target.displayTitle) dejará de aparecer en búsquedas y trending. Reversible desde el panel admin.")
            }
            .alert("Error", isPresented: .init(
                get: { lastError != nil },
                set: { if !$0 { lastError = nil } })
            ) {
                Button("OK") { lastError = nil }
            } message: {
                Text(lastError ?? "")
            }
    }

    private func hide() async {
        do {
            _ = try await AdminService.shared.toggleHidden(
                targetType: target.typeString, targetId: target.id, hidden: true)
            onChanged?()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

extension View {
    /// Añade menú contextual (long-press) con acciones admin/report al card.
    /// Un botón único ("Reportar") se pinta siempre; el bloque "Admin" solo si el user es owner.
    func adminActions(_ target: AdminActionsModifier.Target,
                      onChanged: (() -> Void)? = nil) -> some View {
        modifier(AdminActionsModifier(target: target, onChanged: onChanged))
    }

    // Conveniencia por tipo — para llamar sin construir el enum a mano.
    func adminActionsTrack(id: Int, title: String, artistName: String,
                           youtubeId: String? = nil,
                           releaseDate: String? = nil,
                           coverURL: String? = nil,
                           onChanged: (() -> Void)? = nil) -> some View {
        adminActions(.track(id: id, title: title, artistName: artistName,
                            youtubeId: youtubeId, releaseDate: releaseDate,
                            coverURL: coverURL), onChanged: onChanged)
    }

    func adminActionsArtist(id: Int, name: String,
                            onChanged: (() -> Void)? = nil) -> some View {
        adminActions(.artist(id: id, name: name), onChanged: onChanged)
    }

    func adminActionsAlbum(id: Int, name: String, artistName: String,
                           onChanged: (() -> Void)? = nil) -> some View {
        adminActions(.album(id: id, name: name, artistName: artistName), onChanged: onChanged)
    }
}
