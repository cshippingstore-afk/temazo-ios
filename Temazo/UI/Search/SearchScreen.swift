import SwiftUI

struct SearchScreen: View {
    let onTrackClick: (Track, [Track], Int) -> Void
    var onArtistClick: (Int64?, String?, String?) -> Void = { _, _, _ in }
    var onUserClick: (Int64, String?) -> Void = { _, _ in }

    @State private var query: String = ""
    @State private var tracks: [Track] = []
    @State private var artists: [SearchArtist] = []
    @State private var users: [PublicUserBrief] = []
    @State private var isLoading: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var focused: Bool
    @EnvironmentObject var player: Player
    @StateObject private var history = SearchHistoryRepo.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.textLow).font(.system(size: 16))
                TextField("Buscar canciones y artistas", text: $query)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onChange(of: query) { _, newValue in
                        scheduleSearch(newValue)
                    }
                if !query.isEmpty {
                    Button { query = ""; tracks = []; artists = []; users = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.textLow).font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                    .background(Capsule().fill(Color.bgSurface))
            )
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.06))

            if query.isEmpty {
                historyView
            } else if isLoading && tracks.isEmpty && artists.isEmpty && users.isEmpty {
                ProgressView().tint(.neonPink).padding(.top, 40); Spacer()
            } else if query.count < 2 {
                Spacer()
                Text("Escribe al menos 2 letras").foregroundStyle(.textLow).font(.system(size: 13))
                Spacer()
            } else if tracks.isEmpty && artists.isEmpty && users.isEmpty {
                Spacer()
                Text("Sin resultados para \"\(query)\"").foregroundStyle(.textLow).font(.system(size: 13))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !artists.isEmpty {
                            sectionTitle("Artistas")
                            ForEach(artists) { a in
                                artistRow(a)
                            }
                            Spacer().frame(height: 8)
                        }
                        if !users.isEmpty {
                            sectionTitle("Usuarios")
                            ForEach(users) { u in
                                userRow(u)
                            }
                            Spacer().frame(height: 8)
                        }
                        if !tracks.isEmpty {
                            sectionTitle("Canciones")
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                                TrackRow(
                                    track: t,
                                    rank: nil,
                                    isCurrent: player.state.currentTrack?.id == t.id,
                                    isPlaying: player.state.isPlaying
                                ) {
                                    history.add(query)
                                    focused = false
                                    onTrackClick(t, tracks, idx)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .onAppear { focused = true }
        .onDisappear {
            query = ""
            tracks = []
            artists = []
            users = []
        }
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
    }

    @ViewBuilder
    private func userRow(_ u: PublicUserBrief) -> some View {
        Button {
            history.add(query)
            focused = false
            onUserClick(u.id, u.username)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: u.displayAvatar ?? "")) { phase in
                    if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                    else { Color.bgSurfaceHi }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(u.username.map { "@\($0)" } ?? "@usuario")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Usuario").font(.system(size: 11)).foregroundStyle(Color.textLow)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func artistRow(_ a: SearchArtist) -> some View {
        Button(action: {
            history.add(query)
            focused = false
            onArtistClick(Int64(a.id), a.slug, a.name)
        }) {
            HStack(spacing: 12) {
                if let url = a.displayImage, let u = URL(string: url) {
                    AsyncImage(url: u) { img in img.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { Color.bgSurfaceHi }
                        .frame(width: 48, height: 48).clipShape(Circle())
                } else {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.08))
                        Image(systemName: "person.fill").foregroundStyle(.textLow)
                    }
                    .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text("Artista").font(.system(size: 12)).foregroundStyle(.textLow)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var historyView: some View {
        if history.items.isEmpty {
            VStack {
                Spacer()
                Text("Escribe para buscar.\nTus búsquedas recientes aparecerán aquí.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Búsquedas recientes")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Spacer()
                        Button("Borrar todo") { history.clearAll() }
                            .font(.system(size: 11))
                            .foregroundStyle(Color.neonPink)
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

                    ForEach(history.items, id: \.self) { q in
                        Button(action: {
                            query = q
                            scheduleSearch(q)
                            history.add(q)
                        }) {
                            HStack(spacing: 14) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(Color.white.opacity(0.4))
                                    .font(.system(size: 18))
                                Text(q).font(.system(size: 14)).foregroundStyle(.white)
                                Spacer()
                                Button { history.remove(q) } label: {
                                    Image(systemName: "xmark").font(.system(size: 14))
                                        .foregroundStyle(Color.white.opacity(0.4))
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func scheduleSearch(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            tracks = []; artists = []; users = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            isLoading = true
            defer { isLoading = false }
            async let trackResp = TemazoAPI.shared.search(trimmed, limit: 20)
            async let userResp = TemazoAPI.shared.userSearch(trimmed, limit: 8)
            do {
                let resp = try await trackResp
                if !Task.isCancelled {
                    let validTracks = resp.tracks.filter { !($0.youtubeId ?? "").isEmpty }
                    tracks = validTracks
                    artists = resp.artists ?? []
                    TemazoAPI.shared.prefetchYouTubeURLs(validTracks.compactMap { $0.youtubeId })
                }
            } catch {
                if !Task.isCancelled { tracks = []; artists = [] }
            }
            if let ur = try? await userResp, !Task.isCancelled {
                users = ur.users
            }
        }
    }
}
