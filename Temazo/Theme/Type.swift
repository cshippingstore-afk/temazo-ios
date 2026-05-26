import SwiftUI

/// Tokens de tipografía centralizados. Paridad con Android `Type.kt`.
/// Uso preferido en código nuevo (los archivos antiguos usan `.system(size:weight:)` inline).
enum TypoToken {
    static let titleLarge: Font = .system(size: 22, weight: .bold)
    static let titleMedium: Font = .system(size: 18, weight: .semibold)
    static let titleSmall: Font = .system(size: 16, weight: .semibold)
    static let bodyLarge: Font = .system(size: 16)
    static let body: Font = .system(size: 14)
    static let bodySmall: Font = .system(size: 12)
    static let labelLarge: Font = .system(size: 14, weight: .semibold)
    static let labelSmall: Font = .system(size: 11, weight: .semibold)
    static let caption: Font = .system(size: 11)
    static let mono: Font = .system(size: 12, weight: .regular, design: .monospaced)
}

extension Font {
    static var temazoTitle: Font { TypoToken.titleLarge }
    static var temazoBody: Font { TypoToken.body }
    static var temazoLabel: Font { TypoToken.labelLarge }
    static var temazoCaption: Font { TypoToken.caption }
}
