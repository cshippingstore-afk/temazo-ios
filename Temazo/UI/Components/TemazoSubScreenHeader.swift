import SwiftUI

/// Sub-header reusable para detail screens (Events, News, EditProfile, etc.)
/// Pinta TemazoTopBar + fila con back chevron + título.
struct TemazoSubScreenHeader: View {
    let title: String
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    @EnvironmentObject var player: Player
    @ObservedObject private var notifs = NotificationsRepo.shared

    var body: some View {
        VStack(spacing: 0) {
            TemazoTopBar(
                isPlaying: player.state.isPlaying,
                unreadNotifs: notifs.unread,
                onAvatarClick: onAvatarClick,
                onBellClick: onBellClick,
                onEventsClick: onEventsClick,
                onNewsClick: onNewsClick
            )
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }
}
