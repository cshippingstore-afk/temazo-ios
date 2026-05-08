import SwiftUI

enum AppTab: Int, Hashable {
    case home, search, account
}

/// Detail navegación — réplica del sealed Detail del Android.
enum Detail: Hashable {
    case artist(id: Int64?, slug: String?, name: String?)
    case album(id: Int64?, slug: String?)
    case history
    case following
    case favorites
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

    @EnvironmentObject var player: Player
    @EnvironmentObject var auth: AuthRepository
    @EnvironmentObject var favorites: FavoritesRepo

    var body: some View {
        ZStack {
            AnimatedNeonBackground()

            VStack(spacing: 0) {
                TemazoTopBar(
                    isPlaying: player.state.isPlaying,
                    currentTab: tab,
                    onTabSelected: { newTab in
                        tab = newTab
                        detailStack.removeAll()
                    }
                )
                ZStack {
                    if let last = detailStack.last {
                        detailView(for: last)
                    } else {
                        switch tab {
                        case .home:    HomeScreen(onTrackClick: onPlay)
                        case .search:  SearchScreen(onTrackClick: onPlay)
                        case .account: AccountScreen(
                            onHistoryClick: { detailStack.append(.history) },
                            onFollowingClick: { detailStack.append(.following) },
                            onFavoritesClick: { detailStack.append(.favorites) },
                            onPlaylistClick: { p in
                                Task { await playPlaylist(p) }
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

            // Toast
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
        .onReceive(NotificationCenter.default.publisher(for: .temazoSwitchToAccountTab)) { _ in
            tab = .account
            detailStack.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .temazoToastLoginRequired)) { _ in
            showToast("Inicia sesión para continuar")
            tab = .account
            detailStack.removeAll()
        }
        // Auto-history al cambiar el currentTrack
        .onChange(of: player.state.currentTrack?.id) { _, newId in
            guard let id = newId else { return }
            guard auth.currentUser != nil else { return }
            Task { _ = try? await TemazoAPI.shared.historyAdd(id, source: "app") }
        }
        // Restaurar sesión + sync favs al arrancar y cuando cambia user
        .task {
            await auth.refreshSession()
            await syncFavs()
        }
        .onChange(of: auth.currentUser?.id) { _, _ in
            Task { await syncFavs() }
        }
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
            tab = .account
            detailStack.removeAll()
            fullPlayerShown = false
            return
        }
        if let t = player.state.currentTrack {
            addToPlaylistTrack = t
        }
    }

    private func playPlaylist(_ p: Playlist) async {
        do {
            let resp = try await TemazoAPI.shared.playlistTracks(p.id)
            let valid = resp.tracks.filter { !($0.youtubeId ?? "").isEmpty }
            guard !valid.isEmpty else { return }
            player.playTrack(valid[0], queue: valid, index: 0)
            TemazoAPI.shared.prefetchYouTubeURLs(valid.compactMap { $0.youtubeId })
        } catch {}
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

// Track tiene que ser Identifiable para el sheet(item:). Ya lo es.

#Preview {
    MainScreen()
        .environmentObject(Player.shared)
        .environmentObject(AuthRepository.shared)
        .environmentObject(FavoritesRepo.shared)
        .environmentObject(SettingsRepo.shared)
}
