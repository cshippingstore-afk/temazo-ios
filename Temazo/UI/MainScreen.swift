import SwiftUI

enum AppTab: Int, Hashable {
    case home, search, account
}

extension Notification.Name {
    static let temazoSwitchToAccountTab = Notification.Name("temazoSwitchToAccountTab")
}

struct MainScreen: View {
    @State private var tab: AppTab = .home
    @State private var fullPlayerShown: Bool = false
    @EnvironmentObject var player: Player

    var body: some View {
        ZStack {
            AnimatedNeonBackground()

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .home:    HomeScreen()
                    case .search:  SearchScreen()
                    case .account: AccountScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if player.state.currentTrack != nil {
                    MiniPlayer(onExpand: { fullPlayerShown = true })
                        .transition(.move(edge: .bottom))
                }

                BottomTabBar(selected: $tab)
            }

            if fullPlayerShown, player.state.currentTrack != nil {
                FullPlayer(onClose: { fullPlayerShown = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.state.currentTrack != nil)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: fullPlayerShown)
        .onReceive(NotificationCenter.default.publisher(for: .temazoSwitchToAccountTab)) { _ in
            tab = .account
        }
    }
}

private struct BottomTabBar: View {
    @Binding var selected: AppTab
    private let items: [(AppTab, String, String)] = [
        (.home, "house.fill", "Inicio"),
        (.search, "magnifyingglass", "Buscar"),
        (.account, "person.crop.circle.fill", "Mi cuenta"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                Button { selected = item.0 } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.1).font(.system(size: 22))
                        Text(item.2).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selected == item.0 ? Color.neonPink : Color.textLow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(.ultraThinMaterial)
        .background(Color.bgRoot.opacity(0.7))
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Color.borderSoft), alignment: .top)
    }
}

#Preview {
    MainScreen()
        .environmentObject(Player.shared)
        .environmentObject(AuthRepository.shared)
        .environmentObject(FavoritesRepo.shared)
        .environmentObject(SettingsRepo.shared)
}
