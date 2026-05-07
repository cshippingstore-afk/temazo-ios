import SwiftUI

/// ModalBottomSheet con las playlists del usuario logado.
/// Tap en una playlist → carga sus tracks y empieza a reproducir.
struct PlaylistPickerSheet: View {
    let onClose: () -> Void
    @EnvironmentObject var auth: AuthRepository
    @EnvironmentObject var player: Player
    @State private var playlists: [Playlist] = []
    @State private var loading = false
    @State private var loadingTracksFor: Int64? = nil
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgRoot.ignoresSafeArea()
                content
            }
            .navigationTitle("Mis playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onClose() } label: {
                        Image(systemName: "xmark").foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(Color.bgRoot, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if auth.currentUser == nil {
            VStack(spacing: 14) {
                Image(systemName: "music.note.list").font(.system(size: 44)).foregroundStyle(.textLow)
                Text("Para ver tus playlists")
                    .font(.system(size: 14)).foregroundStyle(.textMid)
                Button {
                    onClose()
                    NotificationCenter.default.post(name: .temazoSwitchToAccountTab, object: nil)
                } label: {
                    Text("INICIA SESIÓN")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(.neonPink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            Capsule().stroke(Color.neonPink.opacity(0.6), lineWidth: 1)
                        )
                        .shadow(color: .neonPink.opacity(0.3), radius: 8)
                }
            }
        } else if loading && playlists.isEmpty {
            ProgressView().tint(.neonPink)
        } else if let e = error {
            Text(e).font(.system(size: 13)).foregroundStyle(.liveRed).padding()
        } else if playlists.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list").font(.system(size: 40)).foregroundStyle(.textLow)
                Text("Aún no tienes playlists")
                    .font(.system(size: 14)).foregroundStyle(.textMid)
                Text("Crea una desde temazo.es")
                    .font(.system(size: 12)).foregroundStyle(.textLow)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(playlists) { p in
                        Button { Task { await loadAndPlay(p) } } label: {
                            row(for: p)
                        }
                        .buttonStyle(.plain)
                        .disabled(loadingTracksFor != nil)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
    }

    private func row(for p: Playlist) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.bgSurfaceHi)
                    .frame(width: 48, height: 48)
                if let url = p.cover, let u = URL(string: url) {
                    AsyncImage(url: u) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else { Image(systemName: "music.note.list").foregroundStyle(.textLow) }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "music.note.list").foregroundStyle(.neonPink)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                if let n = p.trackCount {
                    Text("\(n) canciones").font(.system(size: 11)).foregroundStyle(.textLow)
                }
            }
            Spacer()
            if loadingTracksFor == p.id {
                ProgressView().tint(.neonPink)
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(.neonPink)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))
    }

    private func load() async {
        guard auth.currentUser != nil else { return }
        loading = true
        defer { loading = false }
        do {
            let resp = try await TemazoAPI.shared.playlists()
            playlists = resp.playlists
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadAndPlay(_ p: Playlist) async {
        loadingTracksFor = p.id
        defer { loadingTracksFor = nil }
        do {
            let resp = try await TemazoAPI.shared.playlistTracks(p.id)
            let valid = resp.tracks.filter { $0.youtubeId != nil && !($0.youtubeId ?? "").isEmpty }
            guard !valid.isEmpty else { return }
            player.playTrack(valid[0], queue: valid, index: 0)
            onClose()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
