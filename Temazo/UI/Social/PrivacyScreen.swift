import SwiftUI

/// Ajustes de privacidad: sesión privada, ocultar "Escuchando ahora",
/// ocultar historial + acceso a "Usuarios bloqueados".
/// Equivalente del Android `PrivacyScreen.kt`.
struct PrivacyScreen: View {
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    /// Callback al pulsar "Usuarios bloqueados →".
    let onBlockedUsers: () -> Void

    @State private var hideNp: Bool = false
    @State private var hideHis: Bool = false
    @State private var priv: Bool = false
    @State private var loaded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            TemazoSubScreenHeader(
                title: "Privacidad",
                onBack: onBack,
                onAvatarClick: onAvatarClick,
                onBellClick: onBellClick,
                onEventsClick: onEventsClick,
                onNewsClick: onNewsClick
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Controla qué ven los demás usuarios sobre tu actividad.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer().frame(height: 20)

                    privacyRow(
                        title: "Sesión privada",
                        desc: "Lo que escuchas no aparece en feeds ni en tu perfil mientras esté activada.",
                        value: $priv
                    )
                    Spacer().frame(height: 14)
                    privacyRow(
                        title: "Ocultar 'Escuchando ahora'",
                        desc: "Esconde la canción actual en tu perfil público.",
                        value: $hideNp
                    )
                    Spacer().frame(height: 14)
                    privacyRow(
                        title: "Ocultar historial",
                        desc: "No mostrar Top mes ni historial en tu perfil público.",
                        value: $hideHis
                    )

                    Spacer().frame(height: 28)
                    Divider().background(Color.white.opacity(0.08))
                    Spacer().frame(height: 18)

                    Button(action: onBlockedUsers) {
                        HStack(spacing: 12) {
                            Image(systemName: "nosign")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.neonPink)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Usuarios bloqueados")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Ver y desbloquear")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .task { await load() }
    }

    private func privacyRow(title: String, desc: String, value: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Toggle("", isOn: value)
                .labelsHidden()
                .tint(Color.neonPink)
                .disabled(!loaded)
                .onChange(of: value.wrappedValue) { _, _ in
                    save()
                }
        }
    }

    private func load() async {
        do {
            let r = try await TemazoAPI.shared.userPrivacyGet()
            if let p = r.privacy {
                hideNp = p.hide_now_playing == 1
                hideHis = p.hide_history == 1
                priv = p.private_session == 1
            }
        } catch {}
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        let hp = hideNp, hh = hideHis, ps = priv
        Task {
            do {
                _ = try await TemazoAPI.shared.userPrivacySet(
                    hideNowPlaying: hp,
                    hideHistory: hh,
                    privateSession: ps
                )
            } catch {}
        }
    }
}
