import SwiftUI

/// Pantalla de perfil de artista — réplica visual del Android ArtistScreen.
/// Header (avatar circular + nombre + seguidores + géneros + botón Seguir) → Bio
/// → Carrusel de álbumes horizontal → Top tracks vertical.
struct ArtistScreen: View {
    let artistId: Int64?
    let artistSlug: String?
    let artistName: String?
    let onBack: () -> Void
    let onAlbumClick: (Int64) -> Void
    let onArtistClick: (Int64) -> Void
    let onPlayTracks: ([Track], Int) -> Void

    @EnvironmentObject var auth: AuthRepository
    @State private var artist: Artist? = nil
    @State private var albums: [AlbumSummary] = []
    @State private var topTracks: [Track] = []
    @State private var loading = true
    @State private var error: String? = nil
    @State private var following = false
    @State private var togglingFollow = false

    var displayName: String { artist?.name ?? artistName ?? "Artista" }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56) // espacio bajo TopBar
                    headerView
                    if !albums.isEmpty {
                        sectionTitle("📀 Álbumes")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(albums) { a in
                                    albumCard(a)
                                }
                            }.padding(.horizontal, 16)
                        }
                    }
                    if !topTracks.isEmpty {
                        sectionTitle("🔥 Top canciones")
                        VStack(spacing: 0) {
                            ForEach(Array(topTracks.enumerated()), id: \.element.id) { idx, t in
                                topTrackRow(t, idx: idx)
                                    .onTapGesture { onPlayTracks(topTracks, idx) }
                            }
                        }
                    }
                    // Bio al final del scroll (sin duplicar foto+nombre arriba)
                    if let bio = artist?.bio, !bio.isEmpty {
                        sectionTitle("ℹ Sobre \(artist?.name ?? displayName)")
                        Text(bio)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer().frame(height: 40)
                }
            }
            // TopBar simple (back + título + spinner)
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(10)
                }
                Text(displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer()
                if loading {
                    ProgressView().tint(Color.neonPink).padding(.trailing, 12)
                }
            }
            .frame(height: 50)
            .padding(.horizontal, 4)
        }
        .task { await load() }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 16) {
            // Foto a la izquierda — 130dp circular (igual que Android v1.52+)
            let photoSize: CGFloat = 130
            if let url = artist.flatMap({ $0.image ?? $0.imageLarge }), let u = makeURL(url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.white.opacity(0.05)
                    }
                }
                .frame(width: photoSize, height: photoSize)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: photoSize, height: photoSize)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Color.white.opacity(0.6))
                    )
            }

            // Columna derecha: nombre + seguidores + género + botón follow
            VStack(alignment: .leading, spacing: 4) {
                Text(artist?.name ?? displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                if let f = artist?.followers, f > 0 {
                    Text("\(formatFollowers(f)) seguidores")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                if let g = artist?.genres, !g.isEmpty {
                    Text(g.prefix(3).joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.neonPink.opacity(0.85))
                        .lineLimit(1)
                }
                if artist?.id != nil {
                    Spacer().frame(height: 4)
                    Button(action: toggleFollow) {
                        HStack(spacing: 4) {
                            if following {
                                Text("✓ Siguiendo")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.neonPink)
                            } else {
                                Text("Seguir")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(following ? AnyView(Color.clear) : AnyView(Color.neonPink))
                        .overlay(Capsule().stroke(Color.neonPink, lineWidth: following ? 1 : 0))
                        .clipShape(Capsule())
                    }
                    .disabled(togglingFollow)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func sectionTitle(_ s: String) -> some View {
        HStack {
            Text(s)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func albumCard(_ a: AlbumSummary) -> some View {
        let cover = makeURL(a.cover ?? a.imageMedium ?? a.imageLarge)
        return Button { onAlbumClick(a.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let u = cover {
                        AsyncImage(url: u) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.05)
                            }
                        }
                    } else {
                        Color.white.opacity(0.05)
                    }
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(a.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                if let r = a.releaseDate, !r.isEmpty {
                    Text(String(r.prefix(4)))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .frame(width: 140)
        }
    }

    private func topTrackRow(_ t: Track, idx: Int) -> some View {
        HStack(spacing: 12) {
            if let u = makeURL(t.coverUrl) {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.05)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white).lineLimit(1)
                if let a = t.album, !a.isEmpty {
                    Text(a).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer()
            Text(t.displayDuration).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func load() async {
        loading = true
        do {
            let r = try await TemazoAPI.shared.artist(id: artistId, slug: artistSlug, name: artistName)
            if r.success, let a = r.artist {
                artist = a
                albums = r.albums
                topTracks = r.topTracks.filter { !($0.youtubeId ?? "").isEmpty }
                error = nil
                if auth.currentUser != nil {
                    await refreshFollowingState()
                }
            } else {
                error = r.error ?? "Artista no encontrado"
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func refreshFollowingState() async {
        guard let aid = artist?.id else { return }
        do {
            let r = try await TemazoAPI.shared.follows()
            following = r.artists.contains(where: { $0.id == aid })
        } catch {}
    }

    private func toggleFollow() {
        guard let aid = artist?.id else { return }
        if auth.currentUser == nil {
            NotificationCenter.default.post(name: .temazoToastLoginRequired, object: nil)
            NotificationCenter.default.post(name: .temazoSwitchToAccountTab, object: nil)
            return
        }
        togglingFollow = true
        Task {
            do {
                let r = try await TemazoAPI.shared.followToggle(artistId: aid)
                if r.ok { following = r.following }
            } catch {}
            togglingFollow = false
        }
    }
}

// MARK: - Helpers comunes (URL absoluta + format followers)

func makeURL(_ raw: String?) -> URL? {
    guard let r = raw, !r.isEmpty else { return nil }
    if r.hasPrefix("http") { return URL(string: r) }
    return URL(string: "https://temazo.es" + (r.hasPrefix("/") ? r : "/" + r))
}

func formatFollowers(_ n: Int64) -> String {
    if n < 1000 { return "\(n)" }
    if n < 1_000_000 {
        let v = Double(n) / 1000.0
        return String(format: "%.1fK", v).replacingOccurrences(of: ".0K", with: "K")
    }
    let v = Double(n) / 1_000_000.0
    return String(format: "%.1fM", v).replacingOccurrences(of: ".0M", with: "M")
}

extension Notification.Name {
    static let temazoToastLoginRequired = Notification.Name("temazoToastLoginRequired")
}
