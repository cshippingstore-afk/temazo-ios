import SwiftUI

/// Pantalla de detalle de una playlist (la del user).
/// Muestra header con portada + título + nº canciones + botón "Reproducir todo" + lista.
struct PlaylistDetailScreen: View {
    let playlistId: Int64
    let playlistName: String?
    var onBack: () -> Void
    var onPlay: (Track, [Track], Int) -> Void

    @State private var tracks: [Track] = []
    @State private var loading: Bool = true
    @State private var error: String? = nil
    @State private var removing: Set<Int64> = []
    @State private var isPublic: Bool = false
    @State private var isCollaborative: Bool = false
    @State private var showRename: Bool = false
    @State private var renameText: String = ""
    @State private var showDelete: Bool = false
    @State private var showDuplicateOK: Bool = false
    @State private var currentName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // TopBar con back + menu
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                Text(currentName.isEmpty ? (playlistName ?? "Playlist") : currentName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button {
                        renameText = currentName.isEmpty ? (playlistName ?? "") : currentName
                        showRename = true
                    } label: { Label("Renombrar", systemImage: "pencil") }

                    Toggle(isPublic ? "Pública" : "Privada", isOn: Binding(
                        get: { isPublic },
                        set: { v in Task { await togglePublic(v) } }
                    ))

                    Toggle(isCollaborative ? "Colaborativa" : "No colaborativa", isOn: Binding(
                        get: { isCollaborative },
                        set: { v in Task { await toggleCollaborative(v) } }
                    ))

                    Button { Task { await duplicate() } } label: {
                        Label("Duplicar", systemImage: "doc.on.doc")
                    }

                    Button { share() } label: {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                    }

                    Divider()
                    Button(role: .destructive) {
                        showDelete = true
                    } label: { Label("Borrar playlist", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 4)

            if loading && tracks.isEmpty {
                ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                Text(err).foregroundStyle(Color.white.opacity(0.7)).padding()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        VStack(spacing: 14) {
                            ZStack {
                                LinearGradient(
                                    colors: [Color.neonPink.opacity(0.6), Color(red: 0.43, green: 0.30, blue: 1.0).opacity(0.6)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlistName ?? "Playlist")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("\(tracks.count) canciones")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

                            Button(action: {
                                if !tracks.isEmpty { onPlay(tracks[0], tracks, 0) }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                    Text("Reproducir todo").fontWeight(.bold)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22).padding(.vertical, 12)
                                .background(Color.neonPink, in: Capsule())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                        .padding(20)

                        if tracks.isEmpty {
                            Text("Esta playlist está vacía")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .padding(.vertical, 40)
                        } else {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                                trackRow(t, index: idx)
                            }
                        }
                        Spacer().frame(height: 80)
                    }
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Renombrar playlist", isPresented: $showRename) {
            TextField("Nombre", text: $renameText)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { Task { await rename() } }
        }
        .alert("¿Borrar playlist?", isPresented: $showDelete) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) { Task { await deleteSelf() } }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
        .alert("Duplicada", isPresented: $showDuplicateOK) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La playlist se ha duplicado a tu librería.")
        }
    }

    // MARK: - Actions

    private func togglePublic(_ v: Bool) async {
        let prev = isPublic
        isPublic = v
        let r = try? await TemazoAPI.shared.playlistSetPublic(playlistId, isPublic: v)
        if r?.ok != true { isPublic = prev }
    }

    private func toggleCollaborative(_ v: Bool) async {
        let prev = isCollaborative
        isCollaborative = v
        let r = try? await TemazoAPI.shared.playlistSetCollaborative(playlistId, collaborative: v)
        if r?.ok != true { isCollaborative = prev }
    }

    private func duplicate() async {
        if let r = try? await TemazoAPI.shared.playlistDuplicate(playlistId),
           r.ok {
            showDuplicateOK = true
        }
    }

    private func rename() async {
        let n = renameText.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let r = try? await TemazoAPI.shared.playlistRename(playlistId, name: n),
           r.ok == true {
            currentName = n
        }
    }

    private func deleteSelf() async {
        _ = try? await TemazoAPI.shared.playlistDelete(playlistId)
        onBack()
    }

    private func share() {
        TemazoShare.sharePlaylist(id: playlistId,
                                  name: currentName.isEmpty ? (playlistName ?? "") : currentName,
                                  ownerUsername: nil)
    }

    @ViewBuilder
    private func trackRow(_ t: Track, index: Int) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: t.coverUrl, size: 48, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(t.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white).lineLimit(1)
                Text(t.artistName ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Quitar de la playlist", systemImage: "minus.circle", role: .destructive) {
                    Task { await remove(t) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay(t, tracks, index)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            let resp = try await TemazoAPI.shared.playlistTracks(playlistId)
            tracks = resp.tracks.filter { !($0.youtubeId ?? "").isEmpty }
            error = nil
        } catch let e {
            error = e.localizedDescription
        }
    }

    private func remove(_ t: Track) async {
        do {
            _ = try await TemazoAPI.shared.playlistRemove(playlistId, trackId: t.id)
            tracks.removeAll { $0.id == t.id }
        } catch {}
    }
}
