import SwiftUI

/// TopBar — réplica del Android v1.54+: logo izquierda · ecualizador · acciones derecha.
/// Acciones: [Events] [News] [Bell+badge] [Avatar]
/// Los tabs viven en la bottom NavigationBar.
struct TemazoTopBar: View {
    let isPlaying: Bool
    var unreadNotifs: Int = 0
    var onAvatarClick: () -> Void = {}
    var onBellClick: () -> Void = {}
    var onEventsClick: () -> Void = {}
    var onNewsClick: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image("logo_temazo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 40)
            EqualizerBars(isActive: isPlaying)
            Spacer()
            // Atajo Eventos (siempre visible, no requiere login)
            Button(action: onEventsClick) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            // Atajo Noticias (siempre visible)
            Button(action: onNewsClick) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            // Campana de notificaciones con badge unread
            Button(action: onBellClick) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 40, height: 40)
                    if unreadNotifs > 0 {
                        Text(unreadNotifs > 9 ? "9+" : "\(unreadNotifs)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.neonPink))
                            .offset(x: -4, y: 4)
                    }
                }
            }
            .buttonStyle(.plain)
            // Avatar — abre AccountScreen como detail
            Button(action: onAvatarClick) {
                ZStack {
                    Circle()
                        .fill(Color.neonPink.opacity(0.18))
                    Circle()
                        .stroke(Color.neonPink.opacity(0.5), lineWidth: 1)
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.neonPink)
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 56)
    }
}

/// AppTab — 4 valores, igual que Android.
enum AppTab: Int, Hashable, CaseIterable {
    case home, top, search, playlists

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .top: return "chart.line.uptrend.xyaxis"
        case .search: return "magnifyingglass"
        case .playlists: return "music.note.list"
        }
    }
    var label: String {
        switch self {
        case .home: return "Inicio"
        case .top: return "Top"
        case .search: return "Buscar"
        case .playlists: return "Playlists"
        }
    }
}

private struct EqualizerBars: View {
    let isActive: Bool
    private let bars = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: isActive ? 0.06 : nil, paused: !isActive)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let h: CGFloat = isActive
                        ? CGFloat(0.3 + 0.7 * abs(sin(t * 4 + Double(i) * 0.7)))
                        : 0.4
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isActive ? Color.neonPink : Color.textLow)
                        .frame(width: 3, height: 18 * h)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                isActive ? Color.neonPink.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .frame(height: 28)
        }
    }
}
