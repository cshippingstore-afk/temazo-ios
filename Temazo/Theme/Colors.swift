import SwiftUI

extension Color {
    // Neon palette (matches Android)
    static let neonPink      = Color(hex: 0xFF2E93)
    static let neonPinkSoft  = Color(hex: 0xFF6BB5)
    static let neonPurple    = Color(hex: 0xA855F7)
    static let neonCyan      = Color(hex: 0x00E5FF)
    static let neonLime      = Color(hex: 0xB6FF1F)

    // Backgrounds
    static let bgRoot        = Color(hex: 0x0A0B16)
    static let bgSurface     = Color(hex: 0x12132B)
    static let bgSurfaceHi   = Color(hex: 0x1B1D3A)
    static let borderSoft    = Color(hex: 0x2A2C4D)

    // Text alphas
    static let textHigh      = Color.white
    static let textMid       = Color.white.opacity(0.8)
    static let textLow       = Color.white.opacity(0.53)
    static let textMuted     = Color.white.opacity(0.33)

    // Status / accents
    static let liveGreen     = Color(hex: 0x22C55E)
    static let liveAmber     = Color(hex: 0xF59E0B)
    static let liveRed       = Color(hex: 0xEF4444)
    static let medalGold     = Color(hex: 0xFFD700)
    static let medalSilver   = Color(hex: 0xC0C0C0)
    static let medalBronze   = Color(hex: 0xCD7F32)
    static let badgeNuevo    = Color(hex: 0xEC4899)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
