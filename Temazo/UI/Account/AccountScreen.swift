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
    let onFollowingClick: () -> Void        // artistas que sigo
    let onFavoritesClick: () -> Void
    let onPlaylistClick: (Playlist) -> Void
    var onPublicProfileClick: (() -> Void)? = nil
    var onRecapClick: (() -> Void)? = nil
    var onNotificationsClick: (() -> Void)? = nil
    var onUsersFollowingClick: (() -> Void)? = nil    // usuarios que sigo
    var onUsersFollowersClick: (() -> Void)? = nil    // quién me sigue
    var onUserSearchClick: (() -> Void)? = nil

    @State private var showRegister = false
    @State private var showSettings = false
    @State private var profile: UserProfile? = nil
    @State private var counts = ProfileCounts()
    @State private var playlists: [Playlist] = []
    /// Contadores sociales reales (followers / following users) via userPublic(me).
    @State private var followingUsersCount: Int = 0
    @State private var followersCount: Int = 0
    @State private var socialPollTask: Task<Void, Never>? = nil

    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var renameTarget: Playlist? = nil
    @State private var renameText: String = ""
    @State private var deleteTarget: Playlist? = nil

    @State private var showEditUsername = false
    @State private var usernameText = ""
    @State private var showEditBio = false
    @State private var bioText = ""
    @State private var showPrivacy = false
    @State private var privacy: UserPrivacy? = nil

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var uploadingAvatar = false

    var body: some View {
        // FAB crear playlist eliminado — la creación vive en la pestaña Playlists.
        Group {
            if auth.currentUser != nil {
                profilePanel
            } else {
                LoginPanel(onRegister: { showRegister = true })
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
                await loadSocialCounts()
            } else {
                profile = nil; counts = ProfileCounts(); playlists = []
                followingUsersCount = 0; followersCount = 0
            }
        }
        .onAppear {
            // Polling cada 10 s mientras AccountScreen está visible para mantener
            // los contadores de Siguiendo / Seguidores en tiempo real.
            socialPollTask?.cancel()
            socialPollTask = Task {
                while !Task.isCancelled {
                    if auth.currentUser != nil { await loadSocialCounts() }
                    try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                }
            }
        }
        .onDisappear { socialPollTask?.cancel(); socialPollTask = nil }
    }

    private func loadSocialCounts() async {
        guard let me = auth.currentUser else { return }
        if let r = try? await TemazoAPI.shared.userPublicById(Int64(me.id)) {
            followingUsersCount = r.counts?.following ?? 0
            followersCount = r.counts?.followers ?? 0
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
                bioSection
                Spacer().frame(height: 14)
                accessCards
                Spacer().frame(height: 12)
                socialActions
                Spacer().frame(height: 10)
                actionButtons
                // Listado de playlists eliminado — vive en la pestaña Playlists del bottom nav.
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
        // 3 tarjetas únicas: Siguiendo · Seguidores · Historial
        HStack(spacing: 8) {
            accessCard(emoji: "👥", title: "Siguiendo", count: followingUsersCount,
                       action: { onUsersFollowingClick?() })
            accessCard(emoji: "❤️", title: "Seguidores", count: followersCount,
                       action: { onUsersFollowersClick?() })
            accessCard(emoji: "📜", title: "Historial", count: counts.history,
                       action: onHistoryClick)
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

    /// Fila estilo iOS para acciones del perfil — icono rosa + label + chevron.
    private func actionRow(icon: String, label: String, badge: Int? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.neonPink)
                    .frame(width: 24)
                Text(label).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if let b = badge, b > 0 {
                    Text("\(b)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        // "Salir" se ha movido dentro de SettingsScreen junto con cambiar contraseña, eliminar cuenta y legales.
        Button { showSettings = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape").font(.system(size: 14))
                Text("Ajustes y opciones").font(.system(size: 13))
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Color.neonPink, in: Capsule())
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var bioSection: some View {
        let bio = profile?.bio ?? ""
        VStack(spacing: 6) {
            Button {
                bioText = bio
                showEditBio = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11))
                    Text(bio.isEmpty ? "Añadir bio" : "Editar bio")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .alert("Tu bio", isPresented: $showEditBio) {
            TextField("Cuéntale algo a tus seguidores", text: $bioText)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { Task { await saveBio() } }
        } message: {
            Text("Máximo 500 caracteres")
        }
    }

    private var socialActions: some View {
        VStack(spacing: 8) {
            if (profile?.username ?? "").isEmpty == false {
                actionRow(icon: "person.fill", label: "Ver mi perfil público") { onPublicProfileClick?() }
            }
            actionRow(icon: "chart.bar.fill", label: "Mi recap") { onRecapClick?() }
            actionRow(icon: "magnifyingglass", label: "Buscar usuarios") { onUserSearchClick?() }
            actionRow(icon: "music.mic", label: "Artistas que sigo",
                      badge: counts.follows > 0 ? counts.follows : nil) {
                onFollowingClick()
            }
            actionRow(icon: "music.note.list", label: "Playlists que sigo") {
                NotificationCenter.default.post(name: .temazoOpenPlaylistsFollowing, object: nil)
            }
            actionRow(icon: "bell.fill", label: "Notificaciones") { onNotificationsClick?() }
            actionRow(icon: "lock.shield", label: "Privacidad") {
                Task {
                    if let r = try? await TemazoAPI.shared.userPrivacyGet() { privacy = r.privacy }
                    showPrivacy = true
                }
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showPrivacy) {
            PrivacySheet(current: privacy, onSave: { hideNP, hideH, pr in
                Task {
                    _ = try? await TemazoAPI.shared.userPrivacySet(
                        hideNowPlaying: hideNP, hideHistory: hideH, privateSession: pr
                    )
                    showPrivacy = false
                }
            }, onClose: { showPrivacy = false })
            .presentationDetents([.medium])
        }
    }

    private func saveBio() async {
        _ = try? await TemazoAPI.shared.userBioSet(bioText)
        // Recargar profile para que la pill "Editar bio"/"Añadir bio" refleje el cambio.
        await loadProfile()
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
            // Propagar avatar al store global → TopBar (y todo lo que observe
            // auth.avatarUrl) refresca al instante sin recargar.
            auth.setAvatarUrl(r.user?.displayAvatarUrl)
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
                if r.ok { await loadProfile() }
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
                if r.ok {
                    // Push inmediato al store ANTES de loadProfile para que el TopBar
                    // refresque al instante (loadProfile puede tardar un tick).
                    if let raw = r.avatarUrl, !raw.isEmpty {
                        let abs = raw.hasPrefix("http") ? raw
                            : "https://temazo.es\(raw.hasPrefix("/") ? "" : "/")\(raw)"
                        auth.setAvatarUrl(abs)
                    }
                    await loadProfile()
                }
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

// Sheet de privacidad — hide now playing, hide history, private session.
private struct PrivacySheet: View {
    let current: UserPrivacy?
    let onSave: (Bool, Bool, Bool) -> Void
    let onClose: () -> Void

    @State private var hideNowPlaying: Bool = false
    @State private var hideHistory: Bool = false
    @State private var privateSession: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Tus seguidores no verán qué estás escuchando en tiempo real.")) {
                    Toggle("Ocultar lo que escucho ahora", isOn: $hideNowPlaying)
                }
                Section(footer: Text("Tu historial no será visible para otros usuarios.")) {
                    Toggle("Ocultar mi historial", isOn: $hideHistory)
                }
                Section(footer: Text("Esta sesión no se incluye en estadísticas ni feeds.")) {
                    Toggle("Sesión privada", isOn: $privateSession)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.07, green: 0.04, blue: 0.12))
            .navigationTitle("Privacidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { onClose() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(hideNowPlaying, hideHistory, privateSession)
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                if let c = current {
                    hideNowPlaying = c.hide_now_playing == 1
                    hideHistory = c.hide_history == 1
                    privateSession = c.private_session == 1
                }
            }
        }
    }
}
