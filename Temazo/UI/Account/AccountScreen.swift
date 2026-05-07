import SwiftUI

struct AccountScreen: View {
    @EnvironmentObject var auth: AuthRepository
    @EnvironmentObject var favorites: FavoritesRepo
    @EnvironmentObject var player: Player
    @State private var showRegister = false
    @State private var showSettings = false
    @State private var playlists: [Playlist] = []
    @State private var loadingPlaylist: Int64? = nil

    var body: some View {
        Group {
            if let user = auth.currentUser {
                profilePanel(user: user)
            } else {
                LoginPanel(onRegister: { showRegister = true })
            }
        }
        .background(Color.bgRoot)
        .fullScreenCover(isPresented: $showRegister) {
            RegisterScreen { showRegister = false }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen { showSettings = false }
        }
        .task(id: auth.currentUser?.id) {
            if auth.currentUser != nil { await loadPlaylists() }
        }
    }

    @ViewBuilder
    private func profilePanel(user: SessionUser) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.neonPink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.email).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("ID #\(user.id)").font(.system(size: 11)).foregroundStyle(.textLow)
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 22)).foregroundStyle(.textMid)
                }
                Button { Task { await auth.logout(); playlists = [] } } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 20)).foregroundStyle(.textMid)
                }
            }
            .padding(16)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            HStack {
                Image(systemName: "music.note.list").foregroundStyle(.neonPink)
                Text("Mis playlists (\(playlists.count))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            if playlists.isEmpty {
                Spacer()
                Text("Aún no tienes playlists")
                    .font(.system(size: 13))
                    .foregroundStyle(.textLow)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(playlists) { p in
                            playlistRow(p)
                        }
                    }
                }
            }
        }
    }

    private func playlistRow(_ p: Playlist) -> some View {
        Button {
            Task { await loadAndPlay(p) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.bgSurfaceHi)
                        .frame(width: 48, height: 48)
                    if let url = p.cover, let u = URL(string: url) {
                        AsyncImage(url: u) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "music.note.list").foregroundStyle(.neonPink)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "music.note.list").foregroundStyle(.neonPink)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 15, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text("\(p.trackCount ?? 0) canciones").font(.system(size: 12)).foregroundStyle(.textLow)
                }
                Spacer()
                if loadingPlaylist == p.id {
                    ProgressView().tint(.neonPink)
                } else {
                    Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(.neonPink)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(loadingPlaylist != nil)
    }

    private func loadPlaylists() async {
        do {
            let resp = try await TemazoAPI.shared.playlists()
            playlists = resp.playlists
        } catch {
            print("[Account] playlists load error: \(error)")
        }
    }

    private func loadAndPlay(_ p: Playlist) async {
        loadingPlaylist = p.id
        defer { loadingPlaylist = nil }
        do {
            let resp = try await TemazoAPI.shared.playlistTracks(p.id)
            let valid = resp.tracks.filter { $0.youtubeId != nil && !($0.youtubeId ?? "").isEmpty }
            guard !valid.isEmpty else { return }
            player.playTrack(valid[0], queue: valid, index: 0)
            // prefetch all
            TemazoAPI.shared.prefetchYouTubeURLs(valid.compactMap { $0.youtubeId })
        } catch {
            print("[Account] loadAndPlay error: \(error)")
        }
    }
}

private struct LoginPanel: View {
    @EnvironmentObject var auth: AuthRepository
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var error: String? = nil
    let onRegister: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.neonPink)

            Text("Iniciar sesión")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.borderSoft.opacity(0.8), lineWidth: 1)
                    )

                SecureField("Contraseña", text: $password)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.borderSoft.opacity(0.8), lineWidth: 1)
                    )

                if let e = error {
                    Text(e).font(.system(size: 12)).foregroundStyle(.liveRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await doLogin() }
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Entrar").font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.neonPink))
                    .foregroundStyle(.white)
                    .shadow(color: .neonPink.opacity(0.5), radius: 12)
                }
                .disabled(auth.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            HStack(spacing: 6) {
                Text("¿No tienes cuenta?")
                    .font(.system(size: 13))
                    .foregroundStyle(.textLow)
                Button { onRegister() } label: {
                    Text("Regístrate")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.neonPink)
                }
            }
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func doLogin() async {
        error = nil
        let result = await auth.login(email: email, password: password)
        if case .failure(let e) = result {
            error = e.errorDescription
        }
    }
}
