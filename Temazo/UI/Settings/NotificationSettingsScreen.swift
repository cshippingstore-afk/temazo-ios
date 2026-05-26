import SwiftUI

/// Ajustes de notificaciones push: master switch + un toggle por tipo.
/// Equivalente del Android `NotificationSettingsScreen.kt`.
struct NotificationSettingsScreen: View {
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    @State private var prefs: [String: Bool] = [:]
    @State private var loaded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            TemazoSubScreenHeader(
                title: "Notificaciones",
                onBack: onBack,
                onAvatarClick: onAvatarClick,
                onBellClick: onBellClick,
                onEventsClick: onEventsClick,
                onNewsClick: onNewsClick
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recibe avisos en tiempo real de la actividad social.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer().frame(height: 20)

                    let masterOn = get("master")
                    notifRow(
                        title: "Notificaciones",
                        desc: "Activa o desactiva TODAS las notificaciones push.",
                        kind: "master",
                        disabled: !loaded
                    )

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, 14)

                    notifRow(
                        title: "Nuevos seguidores",
                        desc: "Cuando alguien te empieza a seguir.",
                        kind: "follow_user",
                        disabled: !loaded || !masterOn
                    )
                    Spacer().frame(height: 14)
                    notifRow(
                        title: "Recomendaciones",
                        desc: "Cuando un amigo te recomienda una canción.",
                        kind: "recommend",
                        disabled: !loaded || !masterOn
                    )
                    Spacer().frame(height: 14)
                    notifRow(
                        title: "Playlists colaborativas",
                        desc: "Cuando alguien sigue o añade a tus playlists.",
                        kind: "playlist_followed",
                        disabled: !loaded || !masterOn
                    )
                    Spacer().frame(height: 14)
                    notifRow(
                        title: "Tu recap mensual",
                        desc: "Cuando esté listo tu resumen del mes.",
                        kind: "recap_ready",
                        disabled: !loaded || !masterOn
                    )

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20).padding(.vertical, 20)
            }
        }
        .task { await load() }
    }

    private func notifRow(title: String, desc: String, kind: String, disabled: Bool) -> some View {
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
            Toggle("", isOn: Binding(
                get: { get(kind) },
                set: { set(kind, $0) }
            ))
            .labelsHidden()
            .tint(Color.neonPink)
            .disabled(disabled)
        }
    }

    private func get(_ kind: String, default def: Bool = true) -> Bool {
        prefs[kind] ?? def
    }

    private func set(_ kind: String, _ enabled: Bool) {
        prefs[kind] = enabled
        Task {
            do {
                _ = try await TemazoAPI.shared.notifPrefsSet(kind: kind, enabled: enabled)
            } catch {}
        }
    }

    private func load() async {
        do {
            let r = try await TemazoAPI.shared.notifPrefsGet()
            prefs = r.prefs
        } catch {}
        loaded = true
    }
}
