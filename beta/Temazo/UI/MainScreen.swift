import SwiftUI

/// Detail — réplica del sealed Detail del Android.
enum Detail: Hashable {
    case artist(id: Int64?, slug: String?, name: String?)
    case album(id: Int64?, slug: String?)
    case history
    case following
    case favorites
    case account
    case playlist(id: Int64, name: String?, isLikedDefault: Bool = false)
    case publicPlaylist(id: Int64?, slug: String?)
    case notifications
    case userPublic(id: Int64?, username: String?)
    case usersFollowers(userId: Int64)
    case usersFollowing(userId: Int64)
    case userSearch
    case recap
    case events
    case news
    case editProfile
    case imports
    case playlistsFollowing
    case blockedUsers
    case privacy
    case notificationSettings
    /// BETA v1: pantalla "Descargas" con el catálogo offline
    case downloads
}

extension Notification.Name {
    static let temazoSwitchToAccountTab = Notification.Name("temazoSwitchToAccountTab")
    static let temazoOpenNotificationSettings = Notification.Name("temazoOpenNotificationSettings")
    static let temazoOpenPrivacy = Notification.Name("temazoOpenPrivacy")
    static let temazoOpenEditProfile = Notification.Name("temazoOpenEditProfile")
    static let temazoOpenImports = Notification.Name("temazoOpenImports")
    static let temazoOpenPlaylistsFollowing = Notification.Name("temazoOpenPlaylistsFollowing")
    /// userInfo: ["username": String]
    static let temazoOpenUserByUsername = Notification.Name("temazoOpenUserByUsername")
    /// userInfo: ["playlistId": Int64]
    static let temazoOpenPublicPlaylistById = Notification.Name("temazoOpenPublicPlaylistById")
    /// userInfo: ["slug": String]
    static let temazoOpenArtistBySlug = Notification.Name("temazoOpenArtistBySlug")
    /// userInfo: ["slug": String]  (slug del álbum)
    static let temazoOpenAlbumBySlug = Notification.Name("temazoOpenAlbumBySlug")
}

struct MainScreen: View {
    @State private var tab: AppTab = .home
    @State private var detailStack: [Detail] = []
    @State private var fullPlayerShown: Bool = false
    @State private var addToPlaylistTrack: Track? = nil
    @State private var showLoadPlaylist: Bool = false
    @State private var showCompleteProfile: Bool = false
    @State private var completeProfileNeedsUsername: Bool = false
    @State private var completeProfileNeedsBirthDate: Bool = false
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
                    },
                    onEventsClick: { detailStack.append(.events) },
                    onNewsClick: { detailStack.append(.news) }
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
                                detailStack.append(.playlist(id: p.id, name: p.name,
                                                             isLikedDefault: p.isLikedDefault == true))
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
                onToggleFav: { FavToggle.toggle(t, favRepo: favorites) },
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
        .modifier(MainScreenDeepLinkListeners(detailStack: $detailStack, toastText: $toastText))
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
        .fullScreenCover(isPresented: $showCompleteProfile) {
            CompleteProfileScreen(
                needsUsername: completeProfileNeedsUsername,
                needsBirthDate: completeProfileNeedsBirthDate,
                needsPassword: false,  // iOS no tiene Google OAuth todavía
                onCompleted: { showCompleteProfile = false }
            )
        }
        .task {
            // TopTracksRepo + NotificationsRepo + NowPlayingHeartbeat: start una vez al abrir la app.
            TopTracksRepo.shared.start()
            NowPlayingHeartbeat.shared.start()
            await auth.refreshSession()
            await syncFavs()
            await checkOnboarding()
            await checkProfileCompleteness()
            if auth.currentUser != nil {
                NotificationsRepo.shared.start()
                PushNotificationManager.shared.requestAuthorizationAndRegister()
            }
        }
        .onChange(of: auth.currentUser?.id) { oldId, newId in
            Task {
                await syncFavs()
                await checkProfileCompleteness()
                await checkOnboarding()
                if auth.currentUser != nil {
                    NotificationsRepo.shared.start()
                    PushNotificationManager.shared.requestAuthorizationAndRegister()
                } else if oldId != nil {
                    // Logout: invalidar token APNs en backend
                    PushNotificationManager.shared.unregister()
                }
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

    /// Gate 1.5 — Detecta si el user necesita completar perfil (username/birth_date).
    /// Equivalente del flow Android `CompleteProfileScreen`.
    private func checkProfileCompleteness() async {
        guard auth.currentUser != nil else { showCompleteProfile = false; return }
        do {
            let r = try await TemazoAPI.shared.profile()
            let u = r.user
            let needsUsername = (u?.username ?? "").isEmpty
            let needsBirthDate = (u?.birthDate ?? "").isEmpty
            if needsUsername || needsBirthDate {
                completeProfileNeedsUsername = needsUsername
                completeProfileNeedsBirthDate = needsBirthDate
                showCompleteProfile = true
            } else {
                showCompleteProfile = false
            }
        } catch {
            // Si falla, no bloquear al user.
            showCompleteProfile = false
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
                    detailStack.append(.playlist(id: p.id, name: p.name,
                                                 isLikedDefault: p.isLikedDefault == true))
                },
                onPublicProfileClick: {
                    guard let me = auth.currentUser else { return }
                    detailStack.append(.userPublic(id: Int64(me.id), username: nil))
                },
                onRecapClick: { detailStack.append(.recap) },
                onNotificationsClick: { detailStack.append(.notifications) },
                onUsersFollowingClick: {
                    guard let me = auth.currentUser else { return }
                    detailStack.append(.usersFollowing(userId: Int64(me.id)))
                },
                onUsersFollowersClick: {
                    guard let me = auth.currentUser else { return }
                    detailStack.append(.usersFollowers(userId: Int64(me.id)))
                },
                onUserSearchClick: {
                    detailStack.append(.userSearch)
                },
                onDownloadsClick: {
                    detailStack.append(.downloads)
                }
            )
        case .playlist(let id, let name, let liked):
            PlaylistDetailScreen(
                playlistId: id,
                playlistName: name,
                isLikedDefault: liked,
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
                        let resp = try? await TemazoAPI.shared.trackById(tid)
                        if let track = resp ?? nil {
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
        case .events:
            EventosScreen(
                onBack: { _ = detailStack.popLast() },
                onAvatarClick: { detailStack.append(.account) },
                onBellClick: {
                    if auth.currentUser == nil {
                        showToast("Inicia sesión para ver notificaciones")
                    } else {
                        detailStack.append(.notifications)
                    }
                },
                onNewsClick: {
                    _ = detailStack.popLast()
                    detailStack.append(.news)
                }
            )
        case .news:
            NoticiasScreen(
                onBack: { _ = detailStack.popLast() },
                onAvatarClick: { detailStack.append(.account) },
                onBellClick: {
                    if auth.currentUser == nil {
                        showToast("Inicia sesión para ver notificaciones")
                    } else {
                        detailStack.append(.notifications)
                    }
                },
                onEventsClick: {
                    _ = detailStack.popLast()
                    detailStack.append(.events)
                }
            )
        case .editProfile:
            EditProfileScreen(
                onBack: { _ = detailStack.popLast() },
                onAvatarClick: { detailStack.append(.account) },
                onBellClick: { detailStack.append(.notifications) },
                onEventsClick: { detailStack.append(.events) },
                onNewsClick: { detailStack.append(.news) }
            )
        case .imports:
            ImportsScreen(
                onBack: { _ = detailStack.popLast() },
                onAvatarClick: { detailStack.append(.account) },
                onBellClick: { detailStack.append(.notifications) },
                onEventsClick: { detailStack.append(.events) },
                onNewsClick: { detailStack.append(.news) },
                onOpenUrl: { urlStr in
                    if let url = URL(string: urlStr.hasPrefix("http") ? urlStr : "https://temazo.es\(urlStr)") {
                        UIApplication.shared.open(url)
                    }
                }
            )
        case .playlistsFollowing:
            PlaylistsFollowingScreen(
                onBack: { _ = detailStack.popLast() },
                onAvatarClick: { detailStack.append(.account) },
                onBellClick: { detailStack.append(.notifications) },
                onEventsClick: { detailStack.append(.events) },
                onNewsClick: { detailStack.append(.news) },
                onOpenPlaylist: { pid, slug in
                    detailStack.append(.publicPlaylist(id: pid, slug: slug))
                }
            )
        case .blockedUsers:
            BlockedUsersScreen(
                onBack: { _ = detailStack.popLast() },
                onAvatarClick: { detailStack.append(.account) },
                onBellClick: { detailStack.append(.notifications) },
                onEventsClick: { detailStack.append(.events) },
                onNewsClick: { detailStack.append(.news) },
                onOpenUser: { id, uname in
                    detailStack.append(.userPublic(id: id, username: uname))
                }
            )
        case .privacy:
            PrivacyScreen(
                onBack: { _ = detailStack.popLast() },
                onAvatarClick: { detailStack.append(.account) },
                onBellClick: { detailStack.append(.notifications) },
                onEventsClick: { detailStack.append(.events) },
                onNewsClick: { detailStack.append(.news) },
                onBlockedUsers: { detailStack.append(.blockedUsers) }
            )
        case .notificationSettings:
            NotificationSettingsScreen(
                onBack: { _ = detailStack.popLast() },
                onAvatarClick: { detailStack.append(.account) },
                onBellClick: { detailStack.append(.notifications) },
                onEventsClick: { detailStack.append(.events) },
                onNewsClick: { detailStack.append(.news) }
            )
        case .downloads:
            DownloadsScreen()
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

/// Listeners de NotificationCenter para deep-links y navegación cross-cover.
/// Extraído a ViewModifier para evitar que el body de MainScreen exceda el
/// tiempo de type-check del Swift compiler (era "unable to type-check this
/// expression in reasonable time").
private struct MainScreenDeepLinkListeners: ViewModifier {
    @Binding var detailStack: [Detail]
    @Binding var toastText: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .temazoSwitchToAccountTab)) { _ in
                if !detailStack.contains(.account) { detailStack.append(.account) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenNotificationSettings)) { _ in
                detailStack.append(.notificationSettings)
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenPrivacy)) { _ in
                detailStack.append(.privacy)
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenEditProfile)) { _ in
                detailStack.append(.editProfile)
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenImports)) { _ in
                detailStack.append(.imports)
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenPlaylistsFollowing)) { _ in
                detailStack.append(.playlistsFollowing)
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenUserByUsername)) { notif in
                if let username = notif.userInfo?["username"] as? String {
                    detailStack.append(.userPublic(id: nil, username: username))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenPublicPlaylistById)) { notif in
                if let pid = notif.userInfo?["playlistId"] as? Int64 {
                    detailStack.append(.publicPlaylist(id: pid, slug: nil))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenArtistBySlug)) { notif in
                if let slug = notif.userInfo?["slug"] as? String {
                    detailStack.append(.artist(id: nil, slug: slug, name: nil))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoOpenAlbumBySlug)) { notif in
                if let slug = notif.userInfo?["slug"] as? String {
                    detailStack.append(.album(id: nil, slug: slug))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .temazoToastLoginRequired)) { _ in
                toastText = "Inicia sesión para continuar"
                detailStack = [.account]
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if toastText == "Inicia sesión para continuar" { toastText = nil }
                }
            }
    }
}
