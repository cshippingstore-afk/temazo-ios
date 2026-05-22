import SwiftUI

/// Brazalete diagonal "TOP" en la esquina superior izquierda del cover.
/// Aparece si:
///  - la canción se reproduce desde el tab Top (source = "TOP*"), o
///  - la canción está en el set TopTracksRepo.ids (cualquier top de cualquier país),
///    independientemente del origen de reproducción.
struct SourceRibbon: View {
    let source: String?
    let trackId: Int64?
    var ribbonWidth: CGFloat = 60
    var ribbonHeight: CGFloat = 16
    var fontSize: CGFloat = 9

    @ObservedObject private var topRepo = TopTracksRepo.shared

    var body: some View {
        let isFromTopSource = (source ?? "").hasPrefix("TOP")
        let isInTopGlobally = trackId != nil && topRepo.ids.contains(trackId!)
        if !isFromTopSource && !isInTopGlobally {
            EmptyView()
        } else {
            GeometryReader { geo in
                // Centro del ribbon antes del offset: (w/2, h/2).
                // Queremos que el centro caiga ~en (h, h) para que la diagonal cruce
                // por la esquina del cover (al rotar -45°).
                let offsetX = ribbonHeight - ribbonWidth / 2
                let offsetY = ribbonHeight - ribbonHeight / 2
                ZStack {
                    Text("TOP")
                        .font(.system(size: fontSize, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                }
                .frame(width: ribbonWidth, height: ribbonHeight)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.18, blue: 0.58),
                                 Color(red: 0.43, green: 0.30, blue: 1.0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .rotationEffect(.degrees(-45))
                .offset(x: offsetX, y: offsetY)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .allowsHitTesting(false)
            }
        }
    }
}
