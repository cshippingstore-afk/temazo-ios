import SwiftUI

/// Pantalla de detalle de una playlist (la del user).
/// Muestra header con portada + título + nº canciones + botón "Reproducir todo" + lista.
struct PlaylistDetailScreen: View {
    let playlistId: Int64
    let playlistName: String?
    var onBack: () -> Void
    var onPlay: (Track, [Track], Int) -> Void

    @State private var tracks: [Track] = []
    @State private var loading: Bool = true
    @State private var error: String? = nil
    @State private var removing: Set<Int64> = []

    var body: some View {
        VStack(spacing: 0) {
            // TopBar simple con back
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                Text(playlistName ?? "Playlist")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 4)

            if loading && tracks.isEmpty {
                ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                Text(err).foregroundStyle(Color.white.opacity(0.7)).padding()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        VStack(spacing: 14) {
                            ZStack {
                                LinearGradient(
                                    colors: [Color.neonPink.opacity(0.6), Color(red: 0.43, green: 0.30, blue: 1.0).opacity(0.6)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlistName ?? "Playlist")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("\(tracks.count) canciones")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

                            Button(action: {
                                if !tracks.isEmpty { onPlay(tracks[0], tracks, 0) }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                    Text("Reproducir todo").fontWeight(.bold)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22).padding(.vertical, 12)
                                .background(Color.neonPink, in: Capsule())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                        .padding(20)

                        if tracks.isEmpty {
                            Text("Esta playlist está vacía")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .padding(.vertical, 40)
                        } else {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                                trackRow(t, index: idx)
                            }
                        }
                        Spacer().frame(height: 80)
                    }
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func trackRow(_ t: Track, index: Int) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: t.coverUrl, size: 48, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(t.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white).lineLimit(1)
                Text(t.artistName ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Quitar de la playlist", systemImage: "minus.circle", role: .destructive) {
                    Task { await remove(t) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay(t, tracks, index)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            let resp = try await TemazoAPI.shared.playlistTracks(playlistId)
            tracks = resp.tracks.filter { !($0.youtubeId ?? "").isEmpty }
            error = nil
        } catch let e {
            error = e.localizedDescription
        }
    }

    private func remove(_ t: Track) async {
        do {
            _ = try await TemazoAPI.shared.playlistRemove(playlistId, trackId: t.id)
            tracks.removeAll { $0.id == t.id }
        } catch {}
    }
}
