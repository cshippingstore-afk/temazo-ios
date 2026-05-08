import SwiftUI

/// TopBar — réplica del Android: logo izquierda · ecualizador · bandera · 3 tabs derecha.
/// La nav inferior se elimina; los tabs viven aquí arriba.
struct TemazoTopBar: View {
    let isPlaying: Bool
    let currentTab: AppTab
    let onTabSelected: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image("logo_temazo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 40)
            EqualizerBars(isActive: isPlaying)
            // Bandera del país detectado por Locale
            if let flag = countryFlagFromLocale() {
                Text(flag).font(.system(size: 22))
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(AppTab.all, id: \.self) { tab in
                    Button { onTabSelected(tab) } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(currentTab == tab ? Color.neonPink : Color.white.opacity(0.55))
                            .frame(width: 40, height: 40)
                            .background(
                                currentTab == tab
                                ? Color.neonPink.opacity(0.18)
                                : Color.clear
                            )
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 56)
    }
}

extension AppTab {
    static let all: [AppTab] = [.home, .search, .account]
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .account: return "person.crop.circle.fill"
        }
    }
    var label: String {
        switch self {
        case .home: return "Inicio"
        case .search: return "Buscar"
        case .account: return "Mi cuenta"
        }
    }
}

/// Convierte el código ISO del país del Locale (ES, MX, …) a emoji bandera.
func countryFlagFromLocale() -> String? {
    let cc: String = {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier ?? Locale.current.regionCode ?? ""
        } else {
            return Locale.current.regionCode ?? ""
        }
    }().uppercased()
    guard cc.count == 2, cc.allSatisfy({ $0.isLetter }) else { return nil }
    return cc.unicodeScalars.compactMap { c -> String? in
        guard let s = UnicodeScalar(0x1F1E6 + Int(c.value) - Int(("A" as Unicode.Scalar).value)) else { return nil }
        return String(s)
    }.joined()
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
