import SwiftUI

/// Lista de usuarios que el current user ha bloqueado, con botón "Desbloquear".
/// Equivalente del Android `BlockedUsersScreen.kt`.
struct BlockedUsersScreen: View {
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    /// Abrir perfil público del usuario. Recibe id y opcionalmente username.
    let onOpenUser: (Int64, String?) -> Void

    @State private var users: [PublicUserBrief] = []
    @State private var loading: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            TemazoSubScreenHeader(
                title: "Usuarios bloqueados",
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
            } else if users.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(users, id: \.id) { u in
                            row(u)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "nosign")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.3))
            Text("No has bloqueado a nadie")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
            Text("Los usuarios que bloquees aparecerán aquí, podrás desbloquearlos en cualquier momento")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ u: PublicUserBrief) -> some View {
        HStack(spacing: 12) {
            Button {
                onOpenUser(u.id, u.username)
            } label: {
                HStack(spacing: 12) {
                    avatar(u)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(u.username ?? "usuario")")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        if let b = u.bio, !b.isEmpty {
                            Text(b)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await unblock(u) }
            } label: {
                Text("Desbloquear")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func avatar(_ u: PublicUserBrief) -> some View {
        Group {
            if let url = makeURL(u.displayAvatar) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Color.white.opacity(0.06) }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.neonPink.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    )
            }
        }
    }

    private func load() async {
        loading = true
        do {
            let r = try await TemazoAPI.shared.usersBlocked()
            users = r.users
        } catch {}
        loading = false
    }

    private func unblock(_ u: PublicUserBrief) async {
        do {
            _ = try await TemazoAPI.shared.userBlockToggle(targetId: u.id)
            await load()
        } catch {}
    }
}
