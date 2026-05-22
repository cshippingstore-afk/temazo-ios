import SwiftUI

/// Pantalla "Inicio" — separada del "Top". Muestra:
///  - "Lo último de tus artistas" (feed_following, solo si logueado + sigue a artistas)
///  - "Playlists de Temazo" (discover_playlists, público)
struct InicioScreen: View {
    var onTrackClick: (Track, [Track], Int) -> Void
    var onPlaylistClick: (Int64) -> Void = { _ in }

    @StateObject private var vm = InicioViewModel()
    @EnvironmentObject var auth: AuthRepository
    @EnvironmentObject var player: Player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 12)

                if !vm.followingFeed.isEmpty {
                    sectionTitle("✨ Lo último de tus artistas")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(vm.followingFeed.enumerated()), id: \.element.id) { idx, t in
                                TrackCard(
                                    track: t,
                                    rank: idx + 1,
                                    isCurrent: player.state.currentTrack?.id == t.id,
                                    isPlaying: player.state.currentTrack?.id == t.id && player.state.isPlaying,
                                    onTap: { onTrackClick(t, vm.followingFeed, idx) }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    Spacer().frame(height: 20)
                }

                if !vm.releaseRadar.isEmpty {
                    sectionTitle("📡 Release Radar — novedades para ti")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(vm.releaseRadar.enumerated()), id: \.element.id) { idx, t in
                                TrackCard(track: t, rank: idx + 1,
                                          isCurrent: player.state.currentTrack?.id == t.id,
                                          isPlaying: player.state.currentTrack?.id == t.id && player.state.isPlaying,
                                          onTap: { onTrackClick(t, vm.releaseRadar, idx) })
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    Spacer().frame(height: 20)
                }

                if !vm.dailyMix.isEmpty {
                    sectionTitle("🎯 Daily Mix")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(vm.dailyMix.enumerated()), id: \.element.id) { idx, t in
                                TrackCard(track: t, rank: idx + 1,
                                          isCurrent: player.state.currentTrack?.id == t.id,
                                          isPlaying: player.state.currentTrack?.id == t.id && player.state.isPlaying,
                                          onTap: { onTrackClick(t, vm.dailyMix, idx) })
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    Spacer().frame(height: 20)
                }

                if !vm.friendActivity.isEmpty {
                    sectionTitle("👥 Lo que escuchan tus amigos")
                    VStack(spacing: 8) {
                        ForEach(vm.friendActivity.prefix(8)) { ev in
                            friendActivityRow(ev)
                        }
                    }
                    .padding(.horizontal, 12)
                    Spacer().frame(height: 20)
                }

                if !vm.discoverPlaylists.isEmpty {
                    sectionTitle("🎧 Playlists de Temazo")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(vm.discoverPlaylists) { pl in
                                PublicPlaylistCard(playlist: pl, onClick: { onPlaylistClick(pl.id) })
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    Spacer().frame(height: 20)
                }

                if vm.followingFeed.isEmpty && vm.discoverPlaylists.isEmpty && !vm.loading {
                    Text(auth.currentUser == nil
                         ? "Inicia sesión y sigue a tus artistas favoritos para ver aquí sus últimos lanzamientos."
                         : "Aún no sigues a ningún artista.\nDescubre tus favoritos desde Top o Buscar.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 32)
                }
            }
            .padding(.bottom, 80)
        }
        .refreshable {
            await vm.reload()
        }
        .task { await vm.reload() }
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private func friendActivityRow(_ ev: FriendActivityEvent) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: avatarURL(ev))) { phase in
                if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                else { Color.bgSurfaceHi }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(ev.username.map { "@\($0)" } ?? "Alguien")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(activityText(ev.kind))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMid)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private func avatarURL(_ ev: FriendActivityEvent) -> String {
        guard let raw = ev.avatar_url, !raw.isEmpty else { return "" }
        if raw.hasPrefix("http") { return raw }
        return "https://temazo.es" + (raw.hasPrefix("/") ? raw : "/\(raw)")
    }

    private func activityText(_ kind: String) -> String {
        switch kind {
        case "play": return "escuchó una canción"
        case "follow_artist": return "sigue a un nuevo artista"
        case "follow_user": return "sigue a un nuevo usuario"
        case "playlist_create": return "creó una playlist"
        case "playlist_follow": return "sigue una playlist"
        case "fav": return "le gusta una canción"
        default: return "interactuó"
        }
    }
}

@MainActor
final class InicioViewModel: ObservableObject {
    @Published var followingFeed: [Track] = []
    @Published var discoverPlaylists: [PublicPlaylist] = []
    @Published var releaseRadar: [Track] = []
    @Published var dailyMix: [Track] = []
    @Published var friendActivity: [FriendActivityEvent] = []
    @Published var loading: Bool = true

    func reload() async {
        async let feed = loadFeed()
        async let discover = loadDiscover()
        async let radar = loadReleaseRadar()
        async let mix = loadDailyMix()
        async let activity = loadFriendActivity()
        _ = await (feed, discover, radar, mix, activity)
        loading = false
    }

    private func loadFeed() async {
        if let r = try? await TemazoAPI.shared.feedFollowing(limit: 20) {
            followingFeed = r.tracks.filter { !($0.youtubeId ?? "").isEmpty }
        }
    }

    private func loadDiscover() async {
        if let r = try? await TemazoAPI.shared.discoverPlaylists(limit: 20) {
            discoverPlaylists = r.playlists
        }
    }

    private func loadReleaseRadar() async {
        if let r = try? await TemazoAPI.shared.releaseRadar() {
            releaseRadar = r.tracks.filter { !($0.youtubeId ?? "").isEmpty }
        }
    }

    private func loadDailyMix() async {
        if let r = try? await TemazoAPI.shared.dailyMix() {
            dailyMix = r.tracks.filter { !($0.youtubeId ?? "").isEmpty }
        }
    }

    private func loadFriendActivity() async {
        if let r = try? await TemazoAPI.shared.friendActivity() {
            friendActivity = r.activity
        }
    }
}

/// Card de playlist pública (140×140 con portada + nombre + counts).
struct PublicPlaylistCard: View {
    let playlist: PublicPlaylist
    var onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    LinearGradient(
                        colors: [Color.neonPink.opacity(0.5), Color(red: 0.43, green: 0.30, blue: 1.0).opacity(0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    if let url = playlist.displayCover, let u = URL(string: url) {
                        AsyncImage(url: u) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    } else {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(playlist.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(playlist.followers) seguidores · \(playlist.trackCount) canciones")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
