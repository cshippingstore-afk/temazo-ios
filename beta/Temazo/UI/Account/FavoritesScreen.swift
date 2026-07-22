import SwiftUI

struct FavoritesScreen: View {
    let onBack: () -> Void
    let onTrackClick: (Track, [Track], Int) -> Void

    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var error: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56)
                    if loading {
                        ProgressView().tint(Color.neonPink).padding(40)
                    } else if let e = error {
                        Text(e).foregroundStyle(Color.white.opacity(0.7)).padding(40)
                    } else if tracks.isEmpty {
                        Text("Aún no tienes favoritos").foregroundStyle(Color.white.opacity(0.5)).padding(40)
                    } else {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                            row(t).onTapGesture {
                                onTrackClick(tracks[idx], tracks, idx)
                            }
                        }
                    }
                    Spacer().frame(height: 30)
                }
            }
            topBar
        }
        .task { await load() }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.white).padding(10)
            }
            Text("Favoritos").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.white)
            Spacer()
        }.frame(height: 50).padding(.horizontal, 4)
    }

    private func row(_ t: Track) -> some View {
        HStack(spacing: 12) {
            if let u = makeURL(t.coverUrl) {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Color.white.opacity(0.05) }
                }
                .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Color.white.opacity(0.05).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white).lineLimit(1)
                Text(t.artistName ?? "").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            Button(action: { unfav(t) }) {
                Image(systemName: "heart.fill").foregroundStyle(Color(red: 0.91, green: 0.12, blue: 0.39))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func unfav(_ t: Track) {
        Task {
            do {
                _ = try await TemazoAPI.shared.favToggle(t.id)
                tracks.removeAll { $0.id == t.id }
            } catch {}
        }
    }

    private func load() async {
        loading = true
        do {
            let r = try await TemazoAPI.shared.favs()
            tracks = r.tracks.filter { !($0.youtubeId ?? "").isEmpty }
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
