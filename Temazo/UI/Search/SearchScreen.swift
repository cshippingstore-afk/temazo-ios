import SwiftUI

struct SearchScreen: View {
    let onTrackClick: (Track, [Track], Int) -> Void
    @State private var query: String = ""
    @State private var tracks: [Track] = []
    @State private var isLoading: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var focused: Bool
    @EnvironmentObject var player: Player

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.textLow)
                TextField("Buscar canción, artista, álbum…", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onChange(of: query) { _, newValue in
                        scheduleSearch(newValue)
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.textLow)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if query.count < 2 {
                Spacer()
                Text("Escribe al menos 2 letras para buscar")
                    .foregroundStyle(.textLow).font(.system(size: 14))
                Spacer()
            } else if isLoading && tracks.isEmpty {
                ProgressView().tint(.neonPink).padding(.top, 40)
                Spacer()
            } else if tracks.isEmpty {
                Spacer()
                Text("Sin resultados para “\(query)”")
                    .foregroundStyle(.textLow).font(.system(size: 14))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { idx, t in
                            TrackRow(
                                track: t,
                                rank: nil,
                                isCurrent: player.state.currentTrack?.id == t.id,
                                isPlaying: player.state.isPlaying
                            ) {
                                focused = false
                                onTrackClick(t, tracks, idx)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .onAppear { focused = true }
    }

    private func scheduleSearch(_ q: String) {
        searchTask?.cancel()
        guard q.count >= 2 else {
            tracks = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            if Task.isCancelled { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let resp = try await TemazoAPI.shared.search(q, limit: 20)
                if !Task.isCancelled {
                    let valid = resp.tracks.filter { $0.youtubeId != nil && !($0.youtubeId ?? "").isEmpty }
                    tracks = valid
                    // Pre-resolve TODOS para que cualquier tap sea instantáneo
                    let ids = valid.compactMap { $0.youtubeId }
                    TemazoAPI.shared.prefetchYouTubeURLs(ids)
                }
            } catch {
                if !Task.isCancelled { tracks = [] }
            }
        }
    }
}

#Preview {
    SearchScreen(onTrackClick: { _, _, _ in })
        .environmentObject(Player.shared)
        .preferredColorScheme(.dark)
}
