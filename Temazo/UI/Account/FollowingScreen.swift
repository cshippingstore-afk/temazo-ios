import SwiftUI

struct FollowingScreen: View {
    let onBack: () -> Void
    let onArtistClick: (Int64) -> Void

    @State private var artists: [FollowedArtist] = []
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
                    } else if artists.isEmpty {
                        Text("Aún no sigues a nadie").foregroundStyle(Color.white.opacity(0.5)).padding(40)
                    } else {
                        ForEach(artists) { a in
                            row(a).onTapGesture { onArtistClick(a.id) }
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
            Text("Siguiendo").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.white)
            Spacer()
        }.frame(height: 50).padding(.horizontal, 4)
    }

    private func row(_ a: FollowedArtist) -> some View {
        HStack(spacing: 12) {
            if let u = makeURL(a.displayImage) {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Color.white.opacity(0.05) }
                }
                .frame(width: 48, height: 48).clipShape(Circle())
            } else {
                Circle().fill(Color.neonPink.opacity(0.25))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(Color.white))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.white).lineLimit(1)
                if a.tracksCount > 0 {
                    Text("\(a.tracksCount) canciones").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func load() async {
        loading = true
        do {
            let r = try await TemazoAPI.shared.follows()
            artists = r.artists
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
