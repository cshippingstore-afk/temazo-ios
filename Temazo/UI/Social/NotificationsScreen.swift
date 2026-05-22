import SwiftUI

/// Lista de notificaciones in-app del usuario (follows nuevos, recomendaciones,
/// playlists colaborativas, etc.). El TopBar muestra una campana con el badge
/// de unread; al pulsar se abre esta pantalla y se marca todo como leído al salir.
struct NotificationsScreen: View {
    let onBack: () -> Void
    let onOpenUser: (Int64, String?) -> Void
    let onOpenTrack: (Int64) -> Void

    @ObservedObject private var repo = NotificationsRepo.shared
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if loading && repo.notifications.isEmpty {
                Spacer()
                ProgressView().tint(.neonPink)
                Spacer()
            } else if repo.notifications.isEmpty {
                Spacer()
                Text("Sin notificaciones todavía")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textMid)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(repo.notifications) { n in
                            notifRow(n)
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .background(Color.bgRoot)
        .task {
            loading = true
            _ = await repo.refresh()
            loading = false
        }
        .onDisappear {
            Task { await repo.markAllRead() }
        }
    }

    private var header: some View {
        HStack {
            Button { onBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18))
                    .foregroundStyle(.white)
                    .padding(8)
            }
            Text("Notificaciones")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func notifRow(_ n: TemazoNotification) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: avatarURL(n))) { phase in
                if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                else { Color.bgSurfaceHi }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(message(for: n))
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let at = n.created_at {
                    Text(at.prefix(16).description.replacingOccurrences(of: "T", with: " "))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textLow)
                }
            }
            Spacer()
            if n.isUnread {
                Circle().fill(Color.neonPink).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(n.isUnread ? Color.neonPink.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { handleTap(n) }
    }

    private func handleTap(_ n: TemazoNotification) {
        if let actor = n.actor_id, n.kind == "follow" || n.kind == "user_followed" {
            onOpenUser(actor, n.actor_username)
        } else if n.kind == "recommend", let tid = n.target_id {
            onOpenTrack(tid)
        }
    }

    private func avatarURL(_ n: TemazoNotification) -> String {
        guard let a = n.actor_avatar, !a.isEmpty else { return "" }
        if a.hasPrefix("http") { return a }
        return "https://temazo.es" + (a.hasPrefix("/") ? a : "/\(a)")
    }

    private func message(for n: TemazoNotification) -> String {
        let user = n.actor_username ?? "Alguien"
        switch n.kind {
        case "follow", "user_followed": return "\(user) te empezó a seguir"
        case "recommend": return "\(user) te recomendó una canción"
        case "playlist_added", "playlist_collab_added": return "\(user) añadió canciones a una playlist colaborativa"
        case "playlist_followed": return "\(user) sigue tu playlist"
        default: return "\(user) interactuó contigo"
        }
    }
}
