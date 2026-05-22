import SwiftUI

/// Detail — réplica del sealed Detail del Android.
enum Detail: Hashable {
    case artist(id: Int64?, slug: String?, name: String?)
    case album(id: Int64?, slug: String?)
    case history
    case following
    case favorites
    case account
    case playlist(id: Int64, name: String?)
    case publicPlaylist(id: Int64?, slug: String?)
    case notifications
    case userPublic(id: Int64?, username: String?)
    case usersFollowers(userId: Int64)
    case usersFollowing(userId: Int64)
    case userSearch
    case recap
}

extension Notification.Name {
    static let temazoSwitchToAccountTab = Notification.Name("temazoSwitchToAccountTab")
}

struct MainScreen: View {
    @State private var tab: AppTab = .home
    @State private var detailStack: [Detail] = []
    @State private var fullPlayerShown: Bool = false
    @State private var addToPlaylistTrack: Track? = nil
    @State private var showLoadPlaylist: Bool = false
    @State private var toastText: String? = nil
    @State private var showOnboarding: Bool = false
    @State private var recommendTrack: Track? = nil

    @EnvironmentObject var player: Player
    @EnvironmentObject var auth: AuthRepository
    @EnvironmentObject var favorites: FavoritesRepo
    @StateObject private var optionsBus = TrackOptionsBus.shared
    @ObservedObject private var notifs = NotificationsRepo.shared

    var body: some View {
        ZStack {
            AnimatedNeonBackground()

            VStack(spacing: 0) {
                TemazoTopBar(
                    isPlaying: player.state.isPlaying,
                    unreadNotifs: notifs.unread,
                    onAvatarClick: { detailStack.append(.account) },
                    onBellClick: {
                        if auth.currentUser == nil {
                            showToast("Inicia sesión para ver notificaciones")
                        } else {
                            detailStack.append(.notifications)
                        }
                    }
                )
                ZStack {
                    if let last = detailStack.last {
                        detailView(for: last)
                            .swipeBack { _ = detailStack.popLast() }
                    } else {
                        switch tab {
                        case .home:      InicioScreen(onTrackClick: onPlay,
                                                     onPlaylistClick: { pid in
                                                         detailStack.append(.publicPlaylist(id: pid, slug: nil))
                                                     })
                        case .top:       HomeScreen(onTrackClick: onPlay)
                        case .search:    SearchScreen(
                            onTrackClick: onPlay,
                            onArtistClick: { id, slug, name in
                                detailStack.append(.artist(id: id, slug: slug, name: name))
                            },
                            onUserClick: { id, username in
                                detailStack.append(.userPublic(id: id, username: username))
                            }
                        )
                        case .playlists: PlaylistsScreen(
                            onAvatarClick: { detailStack.append(.account) },
                            onPlaylistClick: { p in
                                detailStack.append(.playlist(id: p.id, name: p.name))
                            },
                            onPublicPlaylistClick: { pid in
                                detailStack.append(.publicPlaylist(id: pid, slug: nil))
                            }
                        )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if player.state.currentTrack != nil {
                    MiniPlayer(
                        onExpand: { fullPlayerShown = true },
                        onCoverClick: handleCoverClick,
                        onArtistClick: handleArtistClick,
                        onAddToPlaylist: handleAddToPlaylist,
                        onLoadPlaylist: { showLoadPlaylist = true }
                    )
                    .transition(.move(edge: .bottom))
                }

                bottomNav
            }

            if fullPlayerShown, player.state.currentTrack != nil {
                FullPlayer(
                    onClose: { fullPlayerShown = false },
                    onCoverClick: { fullPlayerShown = false; handleCoverClick() },
                    onArtistClick: { fullPlayerShown = false; handleArtistClick() },
                    onAddToPlaylist: { handleAddToPlaylist() },
                    onLoadPlaylist: { showLoadPlaylist = true }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }

            if let txt = toastText {
                VStack {
                    Spacer()
                    Text(txt)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 130)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.state.currentTrack != nil)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: fullPlayerShown)
        .animation(.easeInOut(duration: 0.2), value: toastText)
        .sheet(item: $addToPlaylistTrack) { t in
            AddToPlaylistSheet(
                trackId: t.id,
                trackTitle: t.title,
                onDismiss: { addToPlaylistTrack = nil },
                onAdded: { name in
                    addToPlaylistTrack = nil
                    showToast("Añadida a \"\(name)\"")
                }
            )
        }
        .sheet(isPresented: $showLoadPlaylist) {
            PlaylistPickerSheet(onClose: { showLoadPlaylist = false })
        }
        // Sheet de opciones de track (long-press en cualquier TrackRow)
        .sheet(item: $optionsBus.selectedTrack) { t in
            TrackOptionsSheet(
                track: t,
                isFavorite: favorites.contains(t.id),
                onDismiss: { optionsBus.dismiss() },
                onToggleFav: { FavToggle.toggle(trackId: t.id, favRepo: favorites) },
                onAddToPlaylist: {
                    if auth.currentUser == nil {
                        showToast("Inicia sesión para añadir a playlists")
                        detailStack = [.account]
                    } else {
                        addToPlaylistTrack = t
                    }
                },
                onAddToQueue: {
                    player.addToQueue(t)
                    showToast("Añadida a la cola")
                },
                onGoToArtist: {
                    detailStack.append(.artist(id: t.artistId, slug: t.artistSlug, name: t.artistName))
                },
                onGoToAlbum: {
                    detailStack.append(.album(id: t.albumId, slug: t.albumSlug))
                },
                onShare: {
                    TemazoShare.shareTrack(t)
                },
                onRecommend: {
                    if auth.currentUser == nil {
                        showToast("Inicia sesión para recomendar")
                    } else {
                        recommendTrack = t
                    }
                }
            )
        }
        .sheet(item: $recommendTrack) { t in
            RecommendTrackSheet(track: t, onClose: { recommendTrack = nil })
                .presentationDetents([.medium, .large])
        }
        .onReceive(NotificationCenter.default.publisher(for: .temazoSwitchToAccountTab)) { _ in
            // Mantener compatibilidad: si algo dispara este evento, abrir Account como detail.
            if !detailStack.contains(.account) { detailStack.append(.account) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .temazoToastLoginRequired)) { _ in
            showToast("Inicia sesión para continuar")
            detailStack = [.account]
        }
        .onChange(of: player.state.currentTrack?.id) { _, newId in
            guard let id = newId else { return }
            guard auth.currentUser != nil else { return }
            Task { _ = try? await TemazoAPI.shared.historyAdd(id, source: "app") }
        }
        .fullScreenCover(isPresented: Binding(
            get: { auth.currentUser == nil && !auth.isLoading },
            set: { _ in })
        ) {
            WelcomeScreen()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingScreen(onFinish: { showOnboarding = false })
        }
        .task {
            // TopTracksRepo + NotificationsRepo + NowPlayingHeartbeat: start una vez al abrir la app.
            TopTracksRepo.shared.start()
            NowPlayingHeartbeat.shared.start()
            await auth.refreshSession()
            await syncFavs()
            await checkOnboarding()
            if auth.currentUser != nil { NotificationsRepo.shared.start() }
        }
        .onChange(of: auth.currentUser?.id) { _, _ in
            Task {
                await syncFavs()
                await checkOnboarding()
                if auth.currentUser != nil { NotificationsRepo.shared.start() }
            }
        }
    }

    private func checkOnboarding() async {
        guard auth.currentUser != nil else { showOnboarding = false; return }
        do {
            let r = try await TemazoAPI.shared.onboardingStatus()
            showOnboarding = !r.onboarded
        } catch {
            // En caso de error, no forzar onboarding repetido.
            showOnboarding = false
        }
    }

    // MARK: - Bottom nav
    private var bottomNav: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                let active = (tab == t)
                Button(action: {
                    detailStack.removeAll()  // siempre limpia stack al pulsar tab
                    if tab != t { tab = t }
                }) {
                    // El highlight solo cubre el icono+label, no se extiende hasta el home indicator.
                    VStack(spacing: 2) {
                        Image(systemName: t.icon)
                            .font(.system(size: 18, weight: active ? .bold : .regular))
                        Text(t.label).font(.system(size: 10))
                    }
                    .foregroundStyle(active ? Color.neonPink : Color.white.opacity(0.55))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(
                        active ? Color.neonPink.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .background(Color(red: 0.04, green: 0.04, blue: 0.06))
    }

    @ViewBuilder
    private func detailView(for d: Detail) -> some View {
        switch d {
        case .artist(let id, let slug, let name):
            ArtistScreen(
                artistId: id, artistSlug: slug, artistName: name,
                onBack: { _ = detailStack.popLast() },
                onAlbumClick: { aid in detailStack.append(.album(id: aid, slug: nil)) },
                onArtistClick: { aid in detailStack.append(.artist(id: aid, slug: nil, name: nil)) },
                onPlayTracks: { tracks, idx in
                    if !tracks.isEmpty { onPlay(tracks[idx], tracks, idx) }
                }
            )
        case .album(let id, let slug):
            AlbumScreen(
                albumId: id, albumSlug: slug,
                onBack: { _ = detailStack.popLast() },
                onArtistClick: { aid in detailStack.append(.artist(id: aid, slug: nil, name: nil)) },
                onPlayTracks: { tracks, idx in
                    if !tracks.isEmpty { onPlay(tracks[idx], tracks, idx) }
                }
            )
        case .history:
            HistoryScreen(
                onBack: { _ = detailStack.popLast() },
                onTrackClick: onPlay
            )
        case .following:
            FollowingScreen(
                onBack: { _ = detailStack.popLast() },
                onArtistClick: { aid in detailStack.append(.artist(id: aid, slug: nil, name: nil)) }
            )
        case .favorites:
            FavoritesScreen(
                onBack: { _ = detailStack.popLast() },
                onTrackClick: onPlay
            )
        case .account:
            AccountScreen(
                onHistoryClick: { detailStack.append(.history) },
                onFollowingClick: { detailStack.append(.following) },
                onFavoritesClick: { detailStack.append(.favorites) },
                onPlaylistClick: { p in
                    detailStack.append(.playlist(id: p.id, name: p.name))
                },
                onPublicProfileClick: {
                    guard let me = auth.currentUser else { return }
                    detailStack.append(.userPublic(id: Int64(me.id), username: nil))
                },
                onRecapClick: { detailStack.append(.recap) },
                onNotificationsClick: { detailStack.append(.notifications) }
            )
        case .playlist(let id, let name):
            PlaylistDetailScreen(
                playlistId: id,
                playlistName: name,
                onBack: { _ = detailStack.popLast() },
                onPlay: onPlay
            )
        case .notifications:
            NotificationsScreen(
                onBack: { _ = detailStack.popLast() },
                onOpenUser: { id, username in
                    detailStack.append(.userPublic(id: id, username: username))
                },
                onOpenTrack: { tid in
                    Task {
                        if let t = try? await TemazoAPI.shared.trackById(tid), let track = t {
                            onPlay(track, [track], 0)
                        }
                    }
                }
            )
        case .publicPlaylist(let pid, let slug):
            PublicPlaylistScreen(
                playlistId: pid, slug: slug,
                onBack: { _ = detailStack.popLast() },
                onOpenOwner: { uid, uname in
                    detailStack.append(.userPublic(id: uid, username: uname))
                },
                onPlay: onPlay
            )
        case .recap:
            RecapScreen(onBack: { _ = detailStack.popLast() })
        case .userPublic(let id, let username):
            UserPublicScreen(
                username: username, userId: id,
                onBack: { _ = detailStack.popLast() },
                onOpenArtist: { aid in detailStack.append(.artist(id: aid, slug: nil, name: nil)) },
                onOpenPlaylist: { pid, pname in detailStack.append(.publicPlaylist(id: pid, slug: nil)) },
                onOpenUser: { uid, uname in detailStack.append(.userPublic(id: uid, username: uname)) },
                onOpenFollowers: { uid in detailStack.append(.usersFollowers(userId: uid)) },
                onOpenFollowing: { uid in detailStack.append(.usersFollowing(userId: uid)) }
            )
        case .usersFollowers(let uid):
            UsersListScreen(
                kind: .followers, userId: uid, initialQuery: nil,
                onBack: { _ = detailStack.popLast() },
                onOpen: { id, uname in detailStack.append(.userPublic(id: id, username: uname)) }
            )
        case .usersFollowing(let uid):
            UsersListScreen(
                kind: .following, userId: uid, initialQuery: nil,
                onBack: { _ = detailStack.popLast() },
                onOpen: { id, uname in detailStack.append(.userPublic(id: id, username: uname)) }
            )
        case .userSearch:
            UsersListScreen(
                kind: .search, userId: nil, initialQuery: nil,
                onBack: { _ = detailStack.popLast() },
                onOpen: { id, uname in detailStack.append(.userPublic(id: id, username: uname)) }
            )
        }
    }

    // MARK: - Handlers
    private func onPlay(_ track: Track, _ list: [Track], _ idx: Int) {
        player.playTrack(track, queue: list, index: idx)
    }

    private func handleCoverClick() {
        guard let t = player.state.currentTrack else { return }
        if t.albumId != nil || (t.albumSlug?.isEmpty == false) {
            detailStack.append(.album(id: t.albumId, slug: t.albumSlug))
        }
    }

    private func handleArtistClick() {
        guard let t = player.state.currentTrack else { return }
        if t.artistId != nil || (t.artistSlug?.isEmpty == false) {
            detailStack.append(.artist(id: t.artistId, slug: t.artistSlug, name: t.artistName))
        }
    }

    private func handleAddToPlaylist() {
        if auth.currentUser == nil {
            showToast("Inicia sesión para añadir a playlists")
            detailStack = [.account]
            fullPlayerShown = false
            return
        }
        if let t = player.state.currentTrack {
            addToPlaylistTrack = t
        }
    }

    private func syncFavs() async {
        guard auth.currentUser != nil else {
            favorites.clear()
            return
        }
        do {
            let r = try await TemazoAPI.shared.favs()
            favorites.replaceAll(r.tracks.map { $0.id })
        } catch {}
    }

    private func showToast(_ text: String) {
        toastText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if toastText == text { toastText = nil }
        }
    }
}

#Preview {
    MainScreen()
        .environmentObject(Player.shared)
        .environmentObject(AuthRepository.shared)
        .environmentObject(FavoritesRepo.shared)
        .environmentObject(SettingsRepo.shared)
}
