import SwiftUI

/// Bandera rectangular plana (sin emoji ondulado).
/// Usa flagcdn.com — PNG plano, cacheado por sistema.
struct CountryFlag: View {
    let cc: String
    var height: CGFloat = 14

    var body: some View {
        let width = height * 4.0 / 3.0
        let code = cc.lowercased()
        AsyncImage(url: URL(string: "https://flagcdn.com/w80/\(code).png")) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fill)
            default:
                Color.white.opacity(0.08)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

let HISPANIC_COUNTRIES: [(cc: String, name: String)] = [
    ("ES", "España"),
    ("MX", "México"),
    ("AR", "Argentina"),
    ("CO", "Colombia"),
    ("PE", "Perú"),
    ("VE", "Venezuela"),
    ("CL", "Chile"),
    ("EC", "Ecuador"),
    ("GT", "Guatemala"),
    ("CU", "Cuba"),
    ("BO", "Bolivia"),
    ("DO", "República Dominicana"),
    ("HN", "Honduras"),
    ("PY", "Paraguay"),
    ("SV", "El Salvador"),
    ("NI", "Nicaragua"),
    ("CR", "Costa Rica"),
    ("PA", "Panamá"),
    ("UY", "Uruguay"),
    ("PR", "Puerto Rico"),
    ("GQ", "Guinea Ecuatorial"),
]
