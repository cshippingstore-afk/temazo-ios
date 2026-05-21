import SwiftUI

/// PlaylistsScreen — pestaña dedicada a Playlists del bottom nav.
/// Para perfil/ajustes/contraseña, el usuario pulsa el avatar de la TopBar.
struct PlaylistsScreen: View {
    var onAvatarClick: () -> Void = {}
    var onPlaylistClick: (Playlist) -> Void = { _ in }

    @State private var playlists: [Playlist] = []
    @State private var loading: Bool = true
    @State private var showCreate: Bool = false
    @State private var renaming: Playlist? = nil
    @State private var deleting: Playlist? = nil
    @State private var toastText: String? = nil

    @EnvironmentObject var auth: AuthRepository

    var body: some View {
        ZStack {
            if auth.currentUser == nil {
                notLoggedInView
            } else {
                loggedView
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showCreate) {
            PlaylistNameDialog(title: "Nueva playlist", current: "", confirmLabel: "Crear",
                               onCancel: { showCreate = false },
                               onConfirm: { name in
                                   showCreate = false
                                   Task { await createPlaylist(name) }
                               })
        }
        .sheet(item: $renaming) { p in
            PlaylistNameDialog(title: "Renombrar playlist", current: p.name, confirmLabel: "Guardar",
                               onCancel: { renaming = nil },
                               onConfirm: { newName in
                                   renaming = nil
                                   Task { await rename(p, to: newName) }
                               })
        }
        .alert("Eliminar playlist", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )) {
            Button("Cancelar", role: .cancel) { deleting = nil }
            Button("Eliminar", role: .destructive) {
                if let p = deleting {
                    Task { await deletePlaylist(p) }
                }
                deleting = nil
            }
        } message: {
            Text("¿Seguro que quieres eliminar \"\(deleting?.name ?? "")\"? No se puede deshacer.")
        }
        .overlay(alignment: .bottom) {
            if let txt = toastText {
                Text(txt).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 130)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if auth.currentUser != nil {
                Button(action: { showCreate = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.neonPink)
                        .clipShape(Circle())
                        .shadow(radius: 6)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 90)
            }
        }
    }

    private var notLoggedInView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(Color.neonPink)
            Text("Inicia sesión")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("Crea playlists, guarda favoritos y sincronízalos entre dispositivos.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(action: onAvatarClick) {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                    Text("Acceder a mi cuenta")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Color.neonPink, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loggedView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Tu biblioteca")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

                if loading && playlists.isEmpty {
                    ProgressView().padding(40).frame(maxWidth: .infinity)
                } else if playlists.isEmpty {
                    Text("Aún no tienes playlists.\nPulsa + para crear la primera.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                } else {
                    ForEach(playlists) { p in
                        playlistRow(p)
                    }
                }
                Spacer().frame(height: 100)
            }
        }
    }

    @ViewBuilder
    private func playlistRow(_ p: Playlist) -> some View {
        HStack(spacing: 14) {
            // Icono — gradient + corazón si es liked_default, sino icono playlist
            ZStack {
                if p.isLikedDefault == true {
                    LinearGradient(
                        colors: [Color.neonPink, Color(red: 0.43, green: 0.30, blue: 1.0)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                } else if let url = p.displayCover, let u = URL(string: url) {
                    AsyncImage(url: u) { img in img.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: {
                            Image(systemName: "music.note.list").foregroundStyle(Color.white.opacity(0.6))
                        }
                } else {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(p.isLikedDefault == true ? "Canciones que me gustan" : p.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(p.trackCount ?? 0) canciones")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            // Menú overflow solo para playlists editables
            if p.isLikedDefault != true {
                Menu {
                    Button("Renombrar", systemImage: "pencil") { renaming = p }
                    Button("Eliminar playlist", systemImage: "trash", role: .destructive) {
                        deleting = p
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onPlaylistClick(p) }
    }

    // MARK: - Data
    private func reload() async {
        loading = true
        defer { loading = false }
        guard auth.currentUser != nil else { return }
        do {
            let resp = try await TemazoAPI.shared.playlists()
            playlists = resp.playlists
        } catch {}
    }

    private func createPlaylist(_ name: String) async {
        do {
            _ = try await TemazoAPI.shared.playlistCreate(name: name)
            await reload()
            showToast("\"\(name)\" creada")
        } catch {
            showToast("Error al crear")
        }
    }

    private func rename(_ p: Playlist, to newName: String) async {
        do {
            _ = try await TemazoAPI.shared.playlistRename(p.id, name: newName)
            await reload()
        } catch {
            showToast("Error al renombrar")
        }
    }

    private func deletePlaylist(_ p: Playlist) async {
        do {
            _ = try await TemazoAPI.shared.playlistDelete(p.id)
            await reload()
            showToast("Eliminada")
        } catch {
            showToast("Error al eliminar")
        }
    }

    private func showToast(_ text: String) {
        toastText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastText == text { toastText = nil }
        }
    }
}

/// Dialog reutilizable para crear/renombrar playlist.
struct PlaylistNameDialog: View {
    let title: String
    let current: String
    let confirmLabel: String
    var onCancel: () -> Void
    var onConfirm: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            TextField("Nombre", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
            HStack {
                Button("Cancelar") { onCancel() }
                Spacer()
                Button(confirmLabel) {
                    let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { onConfirm(t) }
                }
                .fontWeight(.bold)
                .foregroundStyle(Color.neonPink)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.10, green: 0.04, blue: 0.18))
        .onAppear { name = current }
        .presentationDetents([.height(220)])
    }
}
