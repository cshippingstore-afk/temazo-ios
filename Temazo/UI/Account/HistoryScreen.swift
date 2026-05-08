import SwiftUI

struct HistoryScreen: View {
    let onBack: () -> Void
    let onTrackClick: (Track, [Track], Int) -> Void

    @State private var items: [HistoryItem] = []
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
                    } else if items.isEmpty {
                        Text("Aún no hay reproducciones")
                            .foregroundStyle(Color.white.opacity(0.5))
                            .padding(40)
                    } else {
                        ForEach(items) { h in
                            row(h).onTapGesture { play(h) }
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white).padding(10)
            }
            Text("Historial").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.white)
            Spacer()
        }.frame(height: 50).padding(.horizontal, 4)
    }

    private func row(_ h: HistoryItem) -> some View {
        HStack(spacing: 12) {
            if let u = makeURL(h.coverMedium) {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Color.white.opacity(0.05) }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Color.white.opacity(0.05)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title ?? "(sin título)").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white).lineLimit(1)
                Text(h.artistName ?? "").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            Text(h.localTimeString).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func play(_ h: HistoryItem) {
        let tracks = items.map { $0.toTrack() }.filter { !($0.youtubeId ?? "").isEmpty }
        let target = h.toTrack()
        guard !(target.youtubeId ?? "").isEmpty else { return }
        let idx = tracks.firstIndex(where: { $0.id == target.id }) ?? 0
        onTrackClick(tracks[idx], tracks, idx)
    }

    private func load() async {
        loading = true
        do {
            let r = try await TemazoAPI.shared.history(limit: 100)
            items = r.items
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
