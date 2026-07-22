import SwiftUI

/// Sheet de Sleep Timer — durations preset (5/10/15/30/45/60 min).
/// Muestra tiempo restante si está activo y permite cancelar.
struct SleepTimerSheet: View {
    let onClose: () -> Void
    @ObservedObject private var timer = SleepTimer.shared

    private let presets: [Int] = [5, 10, 15, 30, 45, 60]

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 4).padding(.top, 10)

            Text("Sleep Timer")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            if timer.isActive {
                VStack(spacing: 8) {
                    Text(format(timer.remainingSec))
                        .font(.system(size: 36, weight: .black))
                        .foregroundStyle(Color.neonCyan)
                    Text("Restante hasta pausa automática")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMid)
                }
                .padding(.vertical, 14)

                Button { timer.cancel(); onClose() } label: {
                    Text("Cancelar timer")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.red.opacity(0.18))
                        .overlay(Capsule().stroke(.red.opacity(0.5), lineWidth: 1))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
            } else {
                Text("La música se pausará tras el tiempo elegido")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMid)
                    .padding(.bottom, 6)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(presets, id: \.self) { m in
                        Button {
                            timer.start(minutes: m)
                            onClose()
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(m)")
                                    .font(.system(size: 22, weight: .black))
                                    .foregroundStyle(.white)
                                Text("min")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textMid)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 70)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.bgSurface))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer().frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.07, green: 0.04, blue: 0.12))
    }

    private func format(_ sec: Int) -> String {
        let m = sec / 60
        let s = sec % 60
        return String(format: "%02d:%02d", m, s)
    }
}
