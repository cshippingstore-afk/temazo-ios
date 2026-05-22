import SwiftUI

/// Perfil público de un usuario. Muestra bio, counts (followers/following/playlists),
/// playlists públicas, artistas seguidos, top tracks/artistas, now_playing.
/// Permite seguir/dejar de seguir, bloquear, reportar.
struct UserPublicScreen: View {
    let username: String?
    let userId: Int64?
    let onBack: () -> Void
    let onOpenArtist: (Int64) -> Void
    let onOpenPlaylist: (Int64, String?) -> Void
    let onOpenUser: (Int64, String?) -> Void

    @State private var data: UserPublicResponse? = nil
    @State private var loading: Bool = false
    @State private var error: String? = nil
    @State private var showReport: Bool = false
    @State private var reportReason: String = ""
    @State private var pollTask: Task<Void, Never>? = nil
    /// Estado optimista local del botón Seguir — actualiza al instante sin esperar al server.
    @State private var followingOverride: Bool? = nil
    @State private var followersDelta: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if loading && data == nil {
                    ProgressView().tint(.neonPink).padding(.top, 60)
                } else if let d = data {
                    userHeader(d)
                    if let bio = d.user?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textMid)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                    }
                    if let np = d.now_playing {
                        nowPlayingCard(np)
                    }
                    countsRow(d)
                    if let pls = d.playlists, !pls.isEmpty {
                        sectionTitle("Playlists públicas")
                        ForEach(pls) { p in
                            playlistRow(p)
                        }
                    }
                    if let artists = d.followed_artists, !artists.isEmpty {
                        sectionTitle("Artistas que sigue")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(artists) { a in
                                    Button { onOpenArtist(a.id) } label: {
                                        VStack(spacing: 6) {
                                            AsyncImage(url: URL(string: a.displayImage ?? "")) { phase in
                                                if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                                                else { Color.bgSurfaceHi }
                                            }
                                            .frame(width: 70, height: 70)
                                            .clipShape(Circle())
                                            Text(a.name)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .frame(width: 72)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                    Spacer(minLength: 40)
                } else if let e = error {
                    Text(e).foregroundStyle(.red).padding(.top, 60)
                }
            }
        }
        .background(Color.bgRoot)
        .task { await load() }
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
        .alert("Reportar usuario", isPresented: $showReport) {
            TextField("Motivo", text: $reportReason)
            Button("Cancelar", role: .cancel) {}
            Button("Enviar", role: .destructive) { Task { await sendReport() } }
        }
    }

    private var header: some View {
        HStack {
            Button { onBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18))
                    .foregroundStyle(.white).padding(8)
            }
            Spacer()
            if data?.is_me != true {
                Menu {
                    Button { Task { await toggleBlock() } } label: {
                        Label(data?.blocked_by_me == true ? "Desbloquear" : "Bloquear",
                              systemImage: "hand.raised")
                    }
                    Button(role: .destructive) { showReport = true } label: {
                        Label("Reportar", systemImage: "exclamationmark.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func userHeader(_ d: UserPublicResponse) -> some View {
        VStack(spacing: 12) {
            AsyncImage(url: URL(string: d.user?.displayAvatar ?? "")) { phase in
                if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                else { Color.bgSurfaceHi }
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .overlay(Circle().stroke(LinearGradient(colors: [Color.neonPink, Color.neonCyan],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))

            Text(d.user?.username ?? "@usuario")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            if d.is_me != true {
                let effFollowing = followingOverride ?? (d.followed_by_me == true)
                Button { Task { await toggleFollow() } } label: {
                    Text(effFollowing ? "Siguiendo" : "Seguir")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(
                            Capsule().fill(effFollowing ?
                                           Color.white.opacity(0.15) :
                                           Color.neonPink)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func countsRow(_ d: UserPublicResponse) -> some View {
        let followersEff = (d.counts?.followers ?? 0) + followersDelta
        return HStack(spacing: 24) {
            counterChip("\(max(0, followersEff))", "Seguidores")
            counterChip("\(d.counts?.following ?? 0)", "Siguiendo")
            counterChip("\(d.counts?.public_playlists ?? 0)", "Playlists")
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface.opacity(0.6)))
        .padding(.horizontal, 18)
    }

    private func counterChip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.textLow)
        }
    }

    private func nowPlayingCard(_ np: NowPlayingItem) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: np.cover_medium ?? "")) { phase in
                if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                else { Color.bgSurfaceHi }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("🔊 Escuchando ahora")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.neonCyan)
                Text(np.title ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(np.artist_name ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMid)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.neonCyan.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.neonCyan.opacity(0.3)))
        .padding(.horizontal, 18)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 6)
    }

    private func playlistRow(_ p: PublicPlaylist) -> some View {
        Button { onOpenPlaylist(p.id, p.name) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: p.displayCover ?? "")) { phase in
                    if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                    else { Color.bgSurfaceHi }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("\(p.trackCount) canciones")
                        .font(.system(size: 11)).foregroundStyle(Color.textLow)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.textLow)
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            // Refresca now_playing y counts cada 15s mientras la pantalla esté abierta
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                if Task.isCancelled { return }
                guard let uid = self.data?.user?.id else { continue }
                if let r = try? await TemazoAPI.shared.nowPlayingForUser(uid),
                   r.now_playing != nil {
                    updateNowPlaying(r.now_playing!)
                }
            }
        }
    }

    private func updateNowPlaying(_ np: NowPlayingItem) {
        // No podemos mutar UserPublicResponse (Decodable) sin rehacerla — recargo data.
        Task {
            if let id = userId {
                data = try? await TemazoAPI.shared.userPublicById(id)
            } else if let u = username {
                data = try? await TemazoAPI.shared.userPublic(username: u)
            }
        }
    }

    // MARK: - Actions
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            if let id = userId {
                data = try await TemazoAPI.shared.userPublicById(id)
            } else if let u = username {
                data = try await TemazoAPI.shared.userPublic(username: u)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleFollow() async {
        guard let tid = data?.user?.id else { return }
        // Optimistic UI: flip al instante, contador +/-1, luego confirma con server.
        let wasFollowing = followingOverride ?? (data?.followed_by_me == true)
        followingOverride = !wasFollowing
        followersDelta += wasFollowing ? -1 : 1

        let r = try? await TemazoAPI.shared.userFollowToggle(targetId: tid)
        if let r = r, let serverFollowing = r.following {
            // Sincronizar con el server real
            followingOverride = serverFollowing
            await load()
            followersDelta = 0  // los counts reales ya vienen actualizados
        } else {
            // Si falló, revertir
            followingOverride = wasFollowing
            followersDelta -= wasFollowing ? -1 : 1
        }
    }

    private func toggleBlock() async {
        guard let tid = data?.user?.id else { return }
        _ = try? await TemazoAPI.shared.userBlockToggle(targetId: tid)
        await load()
    }

    private func sendReport() async {
        guard let tid = data?.user?.id, !reportReason.isEmpty else { return }
        _ = try? await TemazoAPI.shared.userReport(targetId: tid, reason: reportReason)
        reportReason = ""
    }
}
