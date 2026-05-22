import SwiftUI

/// Tab "Top" — Apple Music Top 100 por país hispanohablante.
/// Selector de país con bandera rectangular. Cards horizontales + lista vertical.
/// Brazalete TOP automático en el player cuando se reproduce desde aquí.
struct HomeScreen: View {
    let onTrackClick: (Track, [Track], Int) -> Void
    @StateObject private var vm = HomeViewModel()
    @EnvironmentObject var player: Player

    @State private var showCountryPicker: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LiveIndicator(minutes: vm.lastUpdateMin)
                    if vm.fallback {
                        Text("(fallback)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    Spacer()
                    Button(action: { showCountryPicker = true }) {
                        HStack(spacing: 6) {
                            CountryFlag(cc: vm.country, height: 14)
                            Text(vm.country)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                if vm.isLoading && vm.tracks.isEmpty {
                    ProgressView().tint(.neonPink)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else if vm.tracks.isEmpty {
                    Text("Sin datos del Top de \(vm.country) aún")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    Text("🍎 Top 100 \(countryName(vm.country))")
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
                                    onTrackClick(t, vm.tracks, idx)
                                    Player.shared.state.source = "TOP_\(vm.country)"
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
                                onTrackClick(t, vm.tracks, idx)
                                Player.shared.state.source = "TOP_\(vm.country)"
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                Spacer(minLength: 30)
            }
        }
        .task { await vm.loadTop() }
        .refreshable { await vm.forceRefresh() }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(current: vm.country, onPick: { cc in
                vm.setCountry(cc)
                showCountryPicker = false
            }, onClose: { showCountryPicker = false })
        }
    }

    private func countryName(_ cc: String) -> String {
        HISPANIC_COUNTRIES.first(where: { $0.cc == cc })?.name ?? cc
    }
}

struct CountryPickerSheet: View {
    let current: String
    var onPick: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(HISPANIC_COUNTRIES, id: \.cc) { item in
                    Button(action: { onPick(item.cc) }) {
                        HStack(spacing: 12) {
                            CountryFlag(cc: item.cc, height: 18)
                            Text(item.name)
                                .font(.system(size: 15, weight: current == item.cc ? .bold : .regular))
                                .foregroundStyle(current == item.cc ? Color.neonPink : .white)
                            Spacer()
                            Text(item.cc).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
                        }
                    }
                    .listRowBackground(current == item.cc ? Color.neonPink.opacity(0.15) : Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.10, green: 0.04, blue: 0.18))
            .navigationTitle("País para el Top")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { onClose() } }
            }
        }
    }
}

#Preview {
    HomeScreen(onTrackClick: { _, _, _ in })
        .environmentObject(Player.shared)
        .preferredColorScheme(.dark)
}
