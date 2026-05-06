import SwiftUI

struct SettingsScreen: View {
    let onClose: () -> Void
    @EnvironmentObject var settings: SettingsRepo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("Reproducción")

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $settings.crossfadeEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Crossfade entre canciones")
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                Text("Transición suave entre temas, sin silencios")
                                    .font(.system(size: 12)).foregroundStyle(.textLow)
                            }
                        }
                        .tint(.neonPink)

                        if settings.crossfadeEnabled {
                            HStack {
                                Text("Duración: \(settings.crossfadeSeconds)s")
                                    .font(.system(size: 13)).foregroundStyle(.textMid)
                                Spacer()
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(settings.crossfadeSeconds) },
                                    set: { settings.crossfadeSeconds = Int($0.rounded()) }
                                ),
                                in: 1...6, step: 1
                            )
                            .tint(.neonPink)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))

                    Text("Más ajustes próximamente")
                        .font(.system(size: 12)).foregroundStyle(.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                }
                .padding(16)
            }
            .background(Color.bgRoot)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onClose() } label: {
                        Image(systemName: "xmark").foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(Color.bgRoot, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.textMuted)
            .tracking(0.8)
    }
}
