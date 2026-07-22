import SwiftUI

/// Listado de playlists públicas que sigo. Equivalente del Android
/// `PlaylistsFollowingScreen.kt`.
struct PlaylistsFollowingScreen: View {
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    /// Abrir detalle de playlist pública. Pasamos id y slug (slug opcional).
    let onOpenPlaylist: (Int64, String?) -> Void

    @State private var items: [PublicPlaylist] = []
    @State private var loading: Bool = true
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            TemazoSubScreenHeader(
                title: "Playlists que sigo",
                onBack: onBack,
                onAvatarClick: onAvatarClick,
                onBellClick: onBellClick,
                onEventsClick: onEventsClick,
                onNewsClick: onNewsClick
            )

            if loading {
                Spacer()
                ProgressView().tint(Color.neonPink)
                Spacer()
            } else if let e = error {
                Spacer()
                Text(e).foregroundStyle(.white.opacity(0.7))
                Spacer()
            } else if items.isEmpty {
                Spacer()
                Text("Aún no sigues ninguna playlist")
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items, id: \.id) { p in
                            row(p)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .task { await load() }
    }

    private func row(_ p: PublicPlaylist) -> some View {
        Button {
            onOpenPlaylist(p.id, p.slug)
        } label: {
            HStack(spacing: 12) {
                if let u = makeURL(p.displayCover) {
                    AsyncImage(url: u) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Color.white.opacity(0.05) }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.neonPink.opacity(0.25))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle(p))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ p: PublicPlaylist) -> String {
        let count = "\(p.trackCount) canciones"
        if let u = p.ownerUsername, !u.isEmpty {
            return "\(count) · @\(u)"
        }
        return count
    }

    private func load() async {
        loading = true
        do {
            let r = try await TemazoAPI.shared.playlistsFollowing()
            items = r.playlists
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
