import SwiftUI

struct HomeScreen: View {
    @StateObject private var vm = HomeViewModel()
    @EnvironmentObject var player: Player

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TemazoTopBar(isPlaying: player.state.isPlaying)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                LiveIndicator(minutes: vm.lastUpdateMin)
                    .padding(.horizontal, 16)

                GenreChips(genres: vm.genres, selected: vm.selectedGenre) { g in
                    Task { await vm.loadTrending(g.id) }
                }
                .padding(.vertical, 4)

                if vm.isLoading && vm.tracks.isEmpty {
                    ProgressView().tint(.neonPink)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    Text("🔥 Más sonadas")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(vm.tracks.prefix(10).enumerated()), id: \.offset) { idx, t in
                                TrackCard(
                                    track: t,
                                    rank: idx + 1,
                                    isCurrent: player.state.currentTrack?.id == t.id,
                                    isPlaying: player.state.isPlaying
                                ) {
                                    player.playTrack(t, queue: vm.tracks, index: idx)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Text("📋 Top completo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    LazyVStack(spacing: 6) {
                        ForEach(Array(vm.tracks.enumerated()), id: \.offset) { idx, t in
                            TrackRow(
                                track: t,
                                rank: idx + 1,
                                isCurrent: player.state.currentTrack?.id == t.id,
                                isPlaying: player.state.isPlaying
                            ) {
                                player.playTrack(t, queue: vm.tracks, index: idx)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                Spacer(minLength: 30)
            }
        }
        .task { await vm.loadTrending(vm.selectedGenre) }
        .refreshable { await vm.forceRefresh() }
    }
}

private struct GenreChips: View {
    let genres: [GenreItem]
    let selected: String
    let onSelect: (GenreItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres) { g in
                    Button { onSelect(g) } label: {
                        HStack(spacing: 4) {
                            Text(g.emoji)
                            Text(g.name).font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selected == g.id ? Color.neonPink : Color.bgSurfaceHi)
                        )
                        .foregroundStyle(selected == g.id ? .white : .textMid)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    HomeScreen()
        .environmentObject(Player.shared)
        .preferredColorScheme(.dark)
}
