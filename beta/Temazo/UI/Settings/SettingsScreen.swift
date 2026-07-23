import SwiftUI

struct SettingsScreen: View {
    let onClose: () -> Void
    @EnvironmentObject var settings: SettingsRepo
    @EnvironmentObject var auth: AuthRepository
    @EnvironmentObject var favorites: FavoritesRepo
    // BETA v1.2.1: observamos DL/lib para status live
    @StateObject private var dm = DownloadManager.shared
    @StateObject private var lib = OfflineLibrary.shared

    @State private var showPasswordChange = false
    @State private var showLogoutConfirm = false
    @State private var showDeleteAccount = false
    @State private var toastText: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // === REPRODUCCIÓN ===
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
                            Slider(value: Binding(
                                get: { Double(settings.crossfadeSeconds) },
                                set: { settings.crossfadeSeconds = Int($0.rounded()) }
                            ), in: 1...6, step: 1)
                            .tint(.neonPink)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))

                    // === DESCARGAS (BETA v1.2) ===
                    sectionTitle("Descargas offline")
                    downloadsSection
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))

                    // === CUENTA (solo si logueado) ===
                    if auth.currentUser != nil {
                        sectionTitle("Cuenta")
                        VStack(spacing: 0) {
                            settingsRow(icon: "person.crop.circle.fill", label: "Editar perfil",
                                        subtitle: "Bio, avatar y playlist destacada") {
                                onClose()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    NotificationCenter.default.post(name: .temazoOpenEditProfile, object: nil)
                                }
                            }
                            Divider().background(Color.white.opacity(0.05))
                            settingsRow(icon: "bell.fill", label: "Notificaciones",
                                        subtitle: "Avisos por tipo (push e in-app)") {
                                onClose()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    NotificationCenter.default.post(name: .temazoOpenNotificationSettings, object: nil)
                                }
                            }
                            Divider().background(Color.white.opacity(0.05))
                            settingsRow(icon: "lock.shield.fill", label: "Privacidad",
                                        subtitle: "Sesión privada, ocultar historial…") {
                                onClose()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    NotificationCenter.default.post(name: .temazoOpenPrivacy, object: nil)
                                }
                            }
                            Divider().background(Color.white.opacity(0.05))
                            settingsRow(icon: "square.and.arrow.down.fill", label: "Importaciones",
                                        subtitle: "Solicitar artistas/canciones") {
                                onClose()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    NotificationCenter.default.post(name: .temazoOpenImports, object: nil)
                                }
                            }
                            Divider().background(Color.white.opacity(0.05))
                            settingsRow(icon: "lock.fill", label: "Cambiar contraseña",
                                        subtitle: "Actualiza tu contraseña de acceso") {
                                showPasswordChange = true
                            }
                            Divider().background(Color.white.opacity(0.05))
                            settingsRow(icon: "rectangle.portrait.and.arrow.right",
                                        label: "Cerrar sesión",
                                        subtitle: auth.currentUser?.email ?? "") {
                                showLogoutConfirm = true
                            }
                            Divider().background(Color.white.opacity(0.05))
                            settingsRow(icon: "trash.fill", label: "Eliminar cuenta",
                                        subtitle: "Borra tu cuenta y todos tus datos",
                                        tint: Color(red: 0.91, green: 0.12, blue: 0.39)) {
                                showDeleteAccount = true
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))
                    }

                    // === LEGAL ===
                    sectionTitle("Información legal")
                    VStack(spacing: 0) {
                        legalRow("Privacidad", url: "https://temazo.es/privacidad")
                        Divider().background(Color.white.opacity(0.05))
                        legalRow("Términos y condiciones", url: "https://temazo.es/terminos")
                        Divider().background(Color.white.opacity(0.05))
                        legalRow("Cookies", url: "https://temazo.es/cookies")
                        Divider().background(Color.white.opacity(0.05))
                        legalRow("Avisos de copyright (DMCA)", url: "https://temazo.es/dmca")
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface))

                    // === VERSIÓN ===
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    Text("Temazo v\(version)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
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
            .overlay(alignment: .bottom) {
                if let txt = toastText {
                    Text(txt).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 30)
                }
            }
            .sheet(isPresented: $showPasswordChange) {
                ChangePasswordSheet(
                    onCancel: { showPasswordChange = false },
                    onSuccess: {
                        showPasswordChange = false
                        showToast("Contraseña actualizada")
                    }
                )
            }
            .alert("Cerrar sesión", isPresented: $showLogoutConfirm) {
                Button("Cancelar", role: .cancel) {}
                Button("Cerrar sesión", role: .destructive) {
                    Task {
                        await auth.logout()
                        favorites.clear()
                        onClose()
                    }
                }
            } message: {
                Text("Tendrás que iniciar sesión de nuevo en este dispositivo.")
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountSheet(
                    onCancel: { showDeleteAccount = false },
                    onSuccess: {
                        showDeleteAccount = false
                        Task {
                            await auth.logout()
                            favorites.clear()
                            onClose()
                        }
                    }
                )
            }
        }
    }

    /// BETA v1.2: sección de descargas — 4 toggles + acción "Descargar todo ahora".
    @ViewBuilder
    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $settings.autoDownloadFavorites) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Descargar favoritos al dar corazón")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("Al pulsar 💖 la canción se guarda en el iPhone")
                        .font(.system(size: 12)).foregroundStyle(.textLow)
                }
            }.tint(.neonPink)

            Toggle(isOn: $settings.autoDownloadMyPlaylists) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Descargar mis playlists")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("Todas las canciones de tus playlists van al iPhone")
                        .font(.system(size: 12)).foregroundStyle(.textLow)
                }
            }.tint(.neonPink)

            Toggle(isOn: $settings.autoDownloadFollowedPlaylists) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Descargar playlists que sigo")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("Cuando sigues una playlist ajena, se descarga entera")
                        .font(.system(size: 12)).foregroundStyle(.textLow)
                }
            }.tint(.neonPink)

            Toggle(isOn: Binding(
                get: { DownloadManager.shared.wifiOnly },
                set: { DownloadManager.shared.wifiOnly = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Solo descargar en WiFi")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("Evita consumir datos móviles (recomendado)")
                        .font(.system(size: 12)).foregroundStyle(.textLow)
                }
            }.tint(.neonPink)

            Toggle(isOn: $settings.offlineMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modo offline")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("Solo reproduce canciones ya descargadas")
                        .font(.system(size: 12)).foregroundStyle(.textLow)
                }
            }.tint(.orange)

            Button {
                Task { await OfflineOrchestrator.shared.syncAllNow() }
                showToast("Sincronizando descargas…")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sincronizar descargas ahora")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color.neonPink.opacity(0.85)))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Status live: descargando · en cola · descargadas + total MB
            downloadStatusRow
        }
    }

    /// Live status observing DownloadManager.$states + OfflineLibrary.$tracks
    @ViewBuilder
    private var downloadStatusRow: some View {
        let states = DownloadManager.shared.states
        let downloading = states.values.filter { if case .downloading = $0 { return true } else { return false } }.count
        let queued = states.values.filter { if case .queued = $0 { return true } else { return false } }.count
        let failed = states.values.filter { if case .failed = $0 { return true } else { return false } }.count
        let n = OfflineLibrary.shared.tracks.count
        let mb = Double(OfflineLibrary.shared.totalBytes()) / 1_048_576
        let mbStr = mb >= 1000 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
        let onWifi = DownloadManager.shared.isOnWifi

        VStack(spacing: 6) {
            HStack(spacing: 12) {
                statBadge(icon: "checkmark.circle.fill", tint: .green,
                          text: "\(n) descargadas")
                if downloading > 0 {
                    statBadge(icon: "arrow.down.circle", tint: .blue,
                              text: "\(downloading) bajando")
                }
                if queued > 0 {
                    statBadge(icon: "hourglass", tint: .yellow,
                              text: "\(queued) en cola")
                }
                if failed > 0 {
                    statBadge(icon: "exclamationmark.triangle.fill", tint: .red,
                              text: "\(failed) fallos")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text("\(mbStr) en el iPhone · red: \(onWifi ? "WiFi ✓" : "Datos móviles")")
                .font(.system(size: 11)).foregroundStyle(.textLow)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func statBadge(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 11))
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.15)))
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.neonPink)
            .tracking(0.8)
    }

    @ViewBuilder
    private func settingsRow(icon: String, label: String, subtitle: String,
                             tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundStyle(tint).font(.system(size: 18)).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(tint)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func legalRow(_ label: String, url: String) -> some View {
        Button(action: {
            if let u = URL(string: url) { UIApplication.shared.open(u) }
        }) {
            HStack {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.white).frame(width: 24)
                Spacer().frame(width: 14)
                Text(label).font(.system(size: 14)).foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func showToast(_ t: String) {
        toastText = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastText == t { toastText = nil }
        }
    }
}

// MARK: - Change password sheet
struct ChangePasswordSheet: View {
    var onCancel: () -> Void
    var onSuccess: () -> Void

    @State private var current = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var error: String? = nil
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Contraseña actual", text: $current)
                    SecureField("Nueva contraseña", text: $new1)
                    SecureField("Repite nueva", text: $new2)
                }
                if let e = error { Text(e).foregroundStyle(.red) }
            }
            .navigationTitle("Cambiar contraseña")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { onCancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loading ? "..." : "Cambiar") { submit() }.disabled(loading)
                }
            }
        }
    }

    private func submit() {
        error = nil
        guard !current.isEmpty, !new1.isEmpty else { error = "Rellena todos los campos"; return }
        guard new1 == new2 else { error = "Las contraseñas no coinciden"; return }
        guard new1.count >= 8 else { error = "Mínimo 8 caracteres con un dígito"; return }
        loading = true
        Task {
            do {
                let r = try await TemazoAPI.shared.passwordChange(current: current, new: new1)
                loading = false
                if r.ok == true {
                    onSuccess()
                } else {
                    error = errorMessage(r.error)
                }
            } catch let e {
                loading = false
                error = e.localizedDescription
            }
        }
    }

    private func errorMessage(_ code: String?) -> String {
        switch code {
        case "wrong_current": return "Contraseña actual incorrecta"
        case "weak": return "Contraseña débil (mínimo 8 con un dígito)"
        case "same_as_old": return "No puede ser igual a la actual"
        case "bad_input": return "Faltan datos"
        default: return code ?? "Error"
        }
    }
}

// MARK: - Delete account sheet
struct DeleteAccountSheet: View {
    var onCancel: () -> Void
    var onSuccess: () -> Void

    @State private var password = ""
    @State private var error: String? = nil
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Eliminar cuenta").foregroundStyle(Color.red)) {
                    Text("Esto borrará permanentemente tu cuenta, favoritos, playlists e historial. No se puede deshacer.")
                        .font(.system(size: 13))
                    SecureField("Confirma tu contraseña", text: $password)
                }
                if let e = error { Text(e).foregroundStyle(.red) }
            }
            .navigationTitle("Eliminar cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { onCancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loading ? "..." : "Eliminar definitivamente") { submit() }
                        .foregroundStyle(.red)
                        .disabled(loading || password.isEmpty)
                }
            }
        }
    }

    private func submit() {
        loading = true
        error = nil
        Task {
            do {
                let r = try await TemazoAPI.shared.deleteAccount(password: password)
                loading = false
                if r.ok == true {
                    onSuccess()
                } else if r.error == "bad_password" {
                    error = "Contraseña incorrecta"
                } else {
                    error = r.error ?? "Error"
                }
            } catch let e {
                loading = false
                error = e.localizedDescription
            }
        }
    }
}
