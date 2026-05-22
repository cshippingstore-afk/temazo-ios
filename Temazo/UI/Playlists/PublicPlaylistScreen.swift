import SwiftUI

/// Vista pública de una playlist de otro usuario.
/// Permite: reproducir, seguir/dejar de seguir, duplicar a mi librería, compartir.
struct PublicPlaylistScreen: View {
    let playlistId: Int64?
    let slug: String?
    let onBack: () -> Void
    let onOpenOwner: (Int64, String?) -> Void
    let onPlay: (Track, [Track], Int) -> Void

    @State private var data: PublicPlaylistResponse? = nil
    @State private var loading: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if loading && data == nil {
                    ProgressView().tint(.neonPink).padding(.top, 60)
                } else if let d = data {
                    cover(d)
                    actions(d)
                    if let tracks = d.tracks {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(tracks.enumerated()), id: \.offset) { idx, t in
                                TrackRow(
                                    track: t, rank: idx + 1,
                                    isCurrent: Player.shared.state.currentTrack?.id == t.id,
                                    isPlaying: Player.shared.state.isPlaying
                                ) {
                                    onPlay(t, tracks, idx)
                                    Player.shared.state.source = "PLAYLIST_PUB_\(d.playlist?.id ?? 0)"
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                Spacer(minLength: 40)
            }
        }
        .background(Color.bgRoot)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Button { onBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18))
                    .foregroundStyle(.white).padding(8)
            }
            Spacer()
            if let p = data?.playlist {
                Button {
                    TemazoShare.sharePlaylist(id: p.id, name: p.name, ownerUsername: p.ownerUsername)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white).padding(8)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func cover(_ d: PublicPlaylistResponse) -> some View {
        VStack(spacing: 10) {
            AsyncImage(url: URL(string: d.playlist?.displayCover ?? "")) { phase in
                if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                else { Color.bgSurfaceHi }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.neonPink.opacity(0.4), radius: 20, y: 8)

            Text(d.playlist?.name ?? "")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if let owner = d.playlist?.ownerUsername, let oid = d.playlist?.ownerId {
                Button { onOpenOwner(oid, owner) } label: {
                    Text("@\(owner)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.neonCyan)
                }
            }

            if let desc = d.playlist?.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMid)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 8) {
                Text("\(d.playlist?.trackCount ?? 0) canciones")
                Text("·")
                Text("\(d.playlist?.followers ?? 0) seguidores")
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.textLow)
        }
        .padding(.top, 4)
    }

    private func actions(_ d: PublicPlaylistResponse) -> some View {
        HStack(spacing: 10) {
            Button { Task { await playAll(d) } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Reproducir")
                }
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color.neonPink))
                .foregroundStyle(.white)
            }

            Button { Task { await toggleFollow() } } label: {
                Text(d.following == true ? "Siguiendo" : "Seguir")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(d.following == true ?
                                               Color.white.opacity(0.15) :
                                               Color.neonPurple.opacity(0.7)))
                    .foregroundStyle(.white)
            }

            Button { Task { await duplicate() } } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .bold))
                    .padding(10)
                    .overlay(Capsule().stroke(Color.white.opacity(0.3)))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let key = slug ?? (playlistId.map(String.init) ?? "")
        data = try? await TemazoAPI.shared.playlistPublic(idOrSlug: key)
    }

    private func playAll(_ d: PublicPlaylistResponse) async {
        guard let tracks = d.tracks, !tracks.isEmpty else { return }
        onPlay(tracks[0], tracks, 0)
        Player.shared.state.source = "PLAYLIST_PUB_\(d.playlist?.id ?? 0)"
    }

    private func toggleFollow() async {
        guard let id = data?.playlist?.id else { return }
        _ = try? await TemazoAPI.shared.playlistFollowToggle(id)
        await load()
    }

    private func duplicate() async {
        guard let id = data?.playlist?.id else { return }
        _ = try? await TemazoAPI.shared.playlistDuplicate(id)
    }
}
