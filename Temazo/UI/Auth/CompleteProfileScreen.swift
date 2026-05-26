import SwiftUI

/// Pantalla OBLIGATORIA tras login Google cuando faltan datos clave
/// (alias, fecha nacimiento, contraseña real).
/// Equivalente del Android `CompleteProfileScreen.kt` — el usuario solo puede
/// salir cerrando sesión.
struct CompleteProfileScreen: View {
    let needsUsername: Bool
    let needsBirthDate: Bool
    let needsPassword: Bool
    let onCompleted: () -> Void

    /// Firma estándar para compatibilidad con el cableado del enum Detail.
    /// CompleteProfile no tiene back/avatar/bell/events/news, pero los aceptamos.
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    init(
        needsUsername: Bool,
        needsBirthDate: Bool,
        needsPassword: Bool,
        onCompleted: @escaping () -> Void,
        onBack: @escaping () -> Void = {},
        onAvatarClick: @escaping () -> Void = {},
        onBellClick: @escaping () -> Void = {},
        onEventsClick: @escaping () -> Void = {},
        onNewsClick: @escaping () -> Void = {}
    ) {
        self.needsUsername = needsUsername
        self.needsBirthDate = needsBirthDate
        self.needsPassword = needsPassword
        self.onCompleted = onCompleted
        self.onBack = onBack
        self.onAvatarClick = onAvatarClick
        self.onBellClick = onBellClick
        self.onEventsClick = onEventsClick
        self.onNewsClick = onNewsClick
    }

    @EnvironmentObject var auth: AuthRepository

    @State private var username: String = ""
    @State private var birthDate: String = ""
    @State private var password: String = ""
    @State private var pwVisible: Bool = false
    @State private var busy: Bool = false
    @State private var err: String? = nil
    @State private var showLogoutConfirm: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.102, green: 0.039, blue: 0.180),
                         Color(red: 0.051, green: 0.020, blue: 0.090),
                         .black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)
                    Text("TEMAZO")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(Color.neonPink)
                    Spacer().frame(height: 20)
                    Text("Casi listo")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(.white)
                    Spacer().frame(height: 8)
                    Text("Para terminar de crear tu cuenta necesitamos unos datos más. Solo te lo pediremos una vez.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Spacer().frame(height: 28)

                    if needsUsername {
                        usernameField
                        Spacer().frame(height: 10)
                    }
                    if needsBirthDate {
                        birthDateField
                        Spacer().frame(height: 10)
                    }
                    if needsPassword {
                        passwordField
                        Spacer().frame(height: 10)
                    }

                    if let e = err {
                        Text(e)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }

                    Spacer().frame(height: 20)
                    Button(action: submit) {
                        Text(busy ? "Guardando…" : "Terminar")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Capsule().fill(Color.neonPink))
                    }
                    .disabled(busy)

                    Spacer().frame(height: 16)
                    Button {
                        showLogoutConfirm = true
                    } label: {
                        Text("Cerrar sesión")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .disabled(busy)

                    Spacer().frame(height: 8)
                    Text("Necesitamos un alias para que otros te encuentren, fecha de nacimiento para recomendarte música y contraseña por si alguna vez quieres entrar sin Google.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .alert("¿Cerrar sesión?", isPresented: $showLogoutConfirm) {
            Button("Cancelar", role: .cancel) { }
            Button("Cerrar sesión", role: .destructive) {
                Task { await auth.logout() }
            }
        } message: {
            Text("Tu cuenta ya está creada. Si cierras sesión ahora, podrás completar el perfil la próxima vez que entres.")
        }
    }

    // MARK: - Fields

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alias público")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            TextField("", text: Binding(
                get: { username },
                set: { input in
                    let filtered = input.lowercased()
                        .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                    username = String(filtered.prefix(30))
                }
            ), prompt: Text("p.ej. juancarlos93").foregroundColor(.white.opacity(0.4)))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            Text("3-30 caracteres · letras, números y _")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var birthDateField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fecha de nacimiento")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            TextField("", text: Binding(
                get: { birthDate },
                set: { input in
                    let digits = input.filter { $0.isNumber }.prefix(8)
                    var out = ""
                    for (i, c) in digits.enumerated() {
                        if i == 4 || i == 6 { out.append("-") }
                        out.append(c)
                    }
                    birthDate = out
                }
            ), prompt: Text("YYYY-MM-DD").foregroundColor(.white.opacity(0.4)))
            .keyboardType(.numberPad)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            Text("Ejemplo: 1995-08-23")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Contraseña")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            HStack {
                Group {
                    if pwVisible {
                        TextField("", text: $password, prompt: Text("").foregroundColor(.white.opacity(0.4)))
                    } else {
                        SecureField("", text: $password, prompt: Text("").foregroundColor(.white.opacity(0.4)))
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundStyle(.white)
                Button {
                    pwVisible.toggle()
                } label: {
                    Image(systemName: pwVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            Text("Mínimo 8 caracteres con al menos un número")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Submit

    private func submit() {
        err = nil
        let u = username.trimmingCharacters(in: .whitespaces).lowercased()
        if needsUsername {
            let ok = u.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil
            if !ok {
                err = "Alias inválido: 3-30 caracteres, solo letras, números y _"
                return
            }
        }
        if needsBirthDate {
            let ok = birthDate.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil
            if !ok {
                err = "Fecha de nacimiento inválida (YYYY-MM-DD)"
                return
            }
        }
        if needsPassword {
            let hasDigit = password.contains(where: { $0.isNumber })
            if password.count < 8 || !hasDigit {
                err = "Contraseña débil: mínimo 8 caracteres con al menos un número"
                return
            }
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                let r = try await TemazoAPI.shared.profileComplete(
                    username: needsUsername ? u : nil,
                    birthDate: needsBirthDate ? birthDate : nil,
                    password: needsPassword ? password : nil
                )
                if r.ok == true {
                    onCompleted()
                } else {
                    err = mapError(r.error) ?? r.error ?? "Error al guardar"
                }
            } catch {
                err = "Error de conexión, inténtalo de nuevo"
            }
        }
    }

    private func mapError(_ code: String?) -> String? {
        switch code {
        case "username_format":   return "Alias inválido: 3-30 caracteres, solo letras, números y _"
        case "username_reserved": return "Ese alias está reservado, prueba otro"
        case "username_taken":    return "Ese alias ya está en uso"
        case "birth_date_invalid": return "Fecha de nacimiento inválida"
        case "password_weak":     return "Contraseña débil: mínimo 8 caracteres con un número"
        default: return nil
        }
    }
}
