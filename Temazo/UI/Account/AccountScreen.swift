import SwiftUI
import PhotosUI

/// Mi cuenta — réplica visual del Android AccountScreen.
/// Avatar circular grande clickable → galería para subir foto.
/// Username editable. 3 access cards (Favoritos · Siguiendo · Historial).
/// Mis playlists con FAB + long-press menu (Renombrar/Borrar).
struct AccountScreen: View {
    @EnvironmentObject var auth: AuthRepository
    @EnvironmentObject var player: Player

    let onHistoryClick: () -> Void
    let onFollowingClick: () -> Void
    let onFavoritesClick: () -> Void
    let onPlaylistClick: (Playlist) -> Void

    @State private var showRegister = false
    @State private var showSettings = false
    @State private var profile: UserProfile? = nil
    @State private var counts = ProfileCounts()
    @State private var playlists: [Playlist] = []

    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var renameTarget: Playlist? = nil
    @State private var renameText: String = ""
    @State private var deleteTarget: Playlist? = nil

    @State private var showEditUsername = false
    @State private var usernameText = ""

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var uploadingAvatar = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if auth.currentUser != nil {
                    profilePanel
                } else {
                    LoginPanel(onRegister: { showRegister = true })
                }
            }
            // FAB crear playlist (solo logueado)
            if auth.currentUser != nil {
                Button { showCreatePlaylist = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.neonPink)
                        .clipShape(Circle())
                        .shadow(color: Color.neonPink.opacity(0.5), radius: 8, y: 4)
                }
                .padding(.bottom, 20)
                .padding(.trailing, 18)
            }
        }
        .fullScreenCover(isPresented: $showRegister) {
            RegisterScreen { showRegister = false }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen { showSettings = false }
        }
        .alert("Nueva playlist", isPresented: $showCreatePlaylist) {
            TextField("Nombre", text: $newPlaylistName)
            Button("Cancelar", role: .cancel) { newPlaylistName = "" }
            Button("Crear") { createPlaylist() }
        }
        .alert("Renombrar playlist", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })
        ) {
            TextField("Nombre", text: $renameText)
            Button("Cancelar", role: .cancel) { renameTarget = nil }
            Button("Guardar") { confirmRename() }
        }
        .alert("¿Borrar playlist?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } })
        ) {
            Button("Cancelar", role: .cancel) { deleteTarget = nil }
            Button("Borrar", role: .destructive) { confirmDelete() }
        } message: {
            Text("\"\(deleteTarget?.name ?? "")\" se borrará. Esta acción no se puede deshacer.")
        }
        .alert("Tu nombre de usuario", isPresented: $showEditUsername) {
            TextField("usuario", text: $usernameText)
                .textInputAutocapitalization(.never)
            Button("Cancelar", role: .cancel) { usernameText = "" }
            Button("Guardar") { saveUsername() }
        } message: {
            Text("3-30 caracteres, solo a-z 0-9 _")
        }
        .onChange(of: photoItem) { _, newItem in
            handlePickedPhoto(newItem)
        }
        .task(id: auth.currentUser?.id) {
            if auth.currentUser != nil {
                await loadProfile()
                await loadPlaylists()
            } else {
                profile = nil; counts = ProfileCounts(); playlists = []
            }
        }
    }

    // MARK: - Profile panel

    @ViewBuilder
    private var profilePanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 16)
                avatarSection
                usernameSection
                Spacer().frame(height: 16)
                accessCards
                Spacer().frame(height: 12)
                actionButtons
                Divider().background(Color.white.opacity(0.06)).padding(.vertical, 12)
                playlistsHeader
                if playlists.isEmpty {
                    Text("Aún no tienes playlists")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(playlists) { p in
                        playlistRow(p)
                    }
                }
                Spacer().frame(height: 80)
            }
        }
    }

    private var avatarSection: some View {
        ZStack {
            ZStack {
                if let url = makeURL(profile?.displayAvatarUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.05)
                        }
                    }
                } else {
                    Color.neonPink.opacity(0.25)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 54))
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(Circle())

            if uploadingAvatar {
                Circle().fill(Color.black.opacity(0.45))
                    .frame(width: 110, height: 110)
                ProgressView().tint(.white)
            }

            // Mini icono cámara
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.neonPink)
                    .clipShape(Circle())
            }
            .offset(x: 38, y: 38)
            .disabled(uploadingAvatar)
        }
        .frame(maxWidth: .infinity)
    }

    private var usernameSection: some View {
        VStack(spacing: 4) {
            Spacer().frame(height: 12)
            HStack(spacing: 6) {
                if let u = profile?.username, !u.isEmpty {
                    Text("@\(u)").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text(auth.currentUser?.email ?? "")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Button {
                    usernameText = profile?.username ?? ""
                    showEditUsername = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            if (profile?.username ?? "").isEmpty == false, let email = auth.currentUser?.email {
                Text(email).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    private var accessCards: some View {
        HStack(spacing: 8) {
            accessCard(emoji: "❤", title: "Favoritos", count: counts.favs, action: onFavoritesClick)
            accessCard(emoji: "👥", title: "Siguiendo", count: counts.follows, action: onFollowingClick)
            accessCard(emoji: "📜", title: "Historial", count: counts.history, action: onHistoryClick)
        }
        .padding(.horizontal, 12)
    }

    private func accessCard(emoji: String, title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(emoji).font(.system(size: 20))
                Text("\(count)").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.neonPink.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button { showSettings = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape").font(.system(size: 14))
                    Text("Ajustes").font(.system(size: 12))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .foregroundStyle(.white)
            }
            Button { Task { await auth.logout(); profile = nil; counts = ProfileCounts(); playlists = [] } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 14))
                    Text("Salir").font(.system(size: 12))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .foregroundStyle(.white)
            }
        }
    }

    private var playlistsHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note.list").foregroundStyle(Color.neonPink)
            Text("Mis playlists (\(playlists.count))")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func playlistRow(_ p: Playlist) -> some View {
        let isLiked = p.isLikedDefault == true
        return HStack(spacing: 12) {
            cover(p)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.system(size: 15, weight: isLiked ? .bold : .medium))
                    .foregroundStyle(isLiked ? Color.neonPink : Color.white)
                    .lineLimit(1)
                Text("\(p.trackCount ?? 0) canciones")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            if isLiked {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color(red: 0.91, green: 0.12, blue: 0.39))
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onPlaylistClick(p) }
        .contextMenu {
            if !isLiked {
                Button {
                    renameText = p.name
                    renameTarget = p
                } label: { Label("Renombrar", systemImage: "pencil") }
                Button(role: .destructive) {
                    deleteTarget = p
                } label: { Label("Borrar", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder
    private func cover(_ p: Playlist) -> some View {
        if p.isLikedDefault == true {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.91, green: 0.12, blue: 0.39), Color(red: 0.61, green: 0.15, blue: 0.69)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "heart.fill").foregroundStyle(.white).font(.system(size: 22))
            }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let url = makeURL(p.displayCover) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { Color.white.opacity(0.05) }
            }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            ZStack {
                Color.neonPink.opacity(0.3)
                Image(systemName: "music.note.list").foregroundStyle(.white)
            }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Actions

    private func loadProfile() async {
        do {
            let r = try await TemazoAPI.shared.profile()
            profile = r.user
            counts = r.counts
        } catch {}
    }

    private func loadPlaylists() async {
        do {
            let r = try await TemazoAPI.shared.playlists()
            playlists = r.playlists
        } catch {}
    }

    private func createPlaylist() {
        let n = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            do {
                let r = try await TemazoAPI.shared.playlistCreate(name: n)
                if r.ok { await loadPlaylists(); await loadProfile() }
            } catch {}
            newPlaylistName = ""
        }
    }

    private func confirmRename() {
        guard let p = renameTarget else { return }
        let n = renameText.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { renameTarget = nil; return }
        Task {
            do {
                _ = try await TemazoAPI.shared.playlistRename(p.id, name: n)
                await loadPlaylists()
            } catch {}
            renameTarget = nil
        }
    }

    private func confirmDelete() {
        guard let p = deleteTarget else { return }
        Task {
            do {
                _ = try await TemazoAPI.shared.playlistDelete(p.id)
                await loadPlaylists(); await loadProfile()
            } catch {}
            deleteTarget = nil
        }
    }

    private func saveUsername() {
        let n = usernameText.trimmingCharacters(in: .whitespaces).lowercased()
        Task {
            do {
                let r = try await TemazoAPI.shared.usernameSet(n)
                if r.ok {
                    profile = profile.map { p in
                        var copy = p
                        // No podemos mutar struct con let; reconstruimos vía decoder
                        copy = (try? JSONDecoder().decode(UserProfile.self, from:
                            JSONSerialization.data(withJSONObject: [
                                "id": p.id,
                                "email": p.email,
                                "username": r.username as Any,
                                "avatar_url": p.avatarUrl as Any
                            ].compactMapValues { v -> Any? in v is NSNull ? nil : v })
                        )) ?? p
                        return copy
                    }
                    await loadProfile()
                }
            } catch {}
            usernameText = ""
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        uploadingAvatar = true
        Task {
            defer { uploadingAvatar = false; photoItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { return }
            // Detectar mime básico por magic bytes
            let mime: String = {
                if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
                if data.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
                if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
                if data.count > 12, data[0..<4] == Data([0x52,0x49,0x46,0x46]), data[8..<12] == Data([0x57,0x45,0x42,0x50]) { return "image/webp" }
                return "image/jpeg"
            }()
            do {
                let r = try await TemazoAPI.shared.avatarUpload(imageData: data, mime: mime)
                if r.ok { await loadProfile() }
            } catch {}
        }
    }
}

// MARK: - LoginPanel (con checkbox "Mantener sesión iniciada")

private struct LoginPanel: View {
    @EnvironmentObject var auth: AuthRepository
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var remember: Bool = true
    @State private var error: String? = nil
    let onRegister: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.neonPink)
            Text("Iniciar sesión").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))
                    .foregroundStyle(.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderSoft.opacity(0.8), lineWidth: 1))
                SecureField("Contraseña", text: $password)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))
                    .foregroundStyle(.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderSoft.opacity(0.8), lineWidth: 1))
                Toggle(isOn: $remember) {
                    Text("Mantener sesión iniciada")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .tint(Color.neonPink)
                if let e = error {
                    Text(e).font(.system(size: 12)).foregroundStyle(Color.liveRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { Task { await doLogin() } } label: {
                    Group {
                        if auth.isLoading { ProgressView().tint(.white) }
                        else { Text("Entrar").font(.system(size: 16, weight: .semibold)) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.neonPink))
                    .foregroundStyle(.white)
                    .shadow(color: Color.neonPink.opacity(0.5), radius: 12)
                }
                .disabled(auth.isLoading)
            }
            .padding(.horizontal, 24).padding(.top, 12)
            HStack(spacing: 6) {
                Text("¿No tienes cuenta?").font(.system(size: 13)).foregroundStyle(Color.textLow)
                Button { onRegister() } label: {
                    Text("Regístrate").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.neonPink)
                }
            }
            .padding(.top, 8)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func doLogin() async {
        error = nil
        let result = await auth.login(email: email, password: password, remember: remember)
        if case .failure(let e) = result { error = e.errorDescription }
    }
}
