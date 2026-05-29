import SwiftUI

/// Sub-header reusable para detail screens (Events, News, EditProfile, etc.)
/// Pinta SOLO la fila con back-chevron + título.
///
/// IMPORTANTE: NO pinta TemazoTopBar — MainScreen ya tiene un TemazoTopBar global
/// arriba que está SIEMPRE visible. Si esta vista pintara su propio TopBar, habría
/// duplicación visual (bug detectado en v2.18.x).
///
/// Los callbacks `onAvatarClick/onBellClick/onEventsClick/onNewsClick` se mantienen
/// en la firma por compatibilidad con todas las pantallas detail que ya los pasan,
/// pero NO se usan internamente. El TopBar global de MainScreen los maneja.
struct TemazoSubScreenHeader: View {
    let title: String
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    var body: some View {
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
        .padding(.vertical, 2)
    }
}
