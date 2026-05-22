import SwiftUI

/// Pantalla de bienvenida para usuarios no logueados.
/// Réplica del Android v1.55+: CoverWall de fondo, 3 botones (registro, Google, login email).
/// Modos: Welcome (default) → Login o Register embebidos.
struct WelcomeScreen: View {
    @EnvironmentObject var auth: AuthRepository

    enum Mode { case welcome, login, register }
    @State private var mode: Mode = .welcome
    @State private var covers: [String] = []
    @State private var busy: Bool = false
    @State private var errorText: String? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1a0a2e), Color(hex: 0x0d0517), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if mode == .welcome && covers.count >= 6 {
                CoverWallBackground(covers: covers)
                LinearGradient(colors: [
                    Color(hex: 0x1a0a2e).opacity(0.55),
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.95)
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            }

            switch mode {
            case .welcome:
                welcomeBody
            case .login:
                EmbeddedLogin(onBack: { mode = .welcome },
                              onSwitchToRegister: { mode = .register })
            case .register:
                RegisterScreen(onClose: { mode = .welcome })
            }
        }
        .task {
            do {
                let r = try await TemazoAPI.shared.trendingByGenre("reggaeton", limit: 30)
                var urls = r.tracks.compactMap { $0.coverUrl }
                urls = Array(Set(urls))
                if urls.isEmpty {
                    let r2 = try await TemazoAPI.shared.trendingByGenre("pop", limit: 30)
                    urls = Array(Set(r2.tracks.compactMap { $0.coverUrl }))
                }
                covers = urls
            } catch {}
        }
    }

    private var welcomeBody: some View {
        VStack(spacing: 0) {
            Spacer().frame(maxHeight: .infinity)

            Image("logo_temazo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 88)

            Spacer().frame(height: 20)

            Text("La música que te mueve")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .tracking(0.5)
                .padding(.horizontal, 12)

            Spacer().frame(height: 10)

            Text("Millones de canciones · Playlists con amigos · Sin límites")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Spacer()

            if let err = errorText {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }

            // Botón principal: crear cuenta
            Button { mode = .register } label: {
                Text("Crea tu cuenta gratis")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(colors: [Color.neonPink, Color.neonPurple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(busy)

            Spacer().frame(height: 10)

            // Google Sign-In (stub — SDK no integrado aún)
            Button { tryGoogle() } label: {
                HStack(spacing: 10) {
                    Text("G")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                    Text("Continuar con Google")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
            .disabled(busy)

            Spacer().frame(height: 10)

            Button { mode = .login } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .font(.system(size: 14))
                    Text("Iniciar sesión con email")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
            .disabled(busy)

            Spacer().frame(height: 16)

            Text("Al continuar aceptas los términos y la política de privacidad.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    private func tryGoogle() {
        // Google Sign-In SDK no integrado en iOS aún — mostramos mensaje.
        errorText = "Google Sign-In aún no está configurado en iOS. Usa email."
    }
}

// MARK: - Cover wall background

private struct CoverWallBackground: View {
    let covers: [String]
    @State private var offset1: CGFloat = 0
    @State private var offset2: CGFloat = 0

    var body: some View {
        let totalWidth: CGFloat = 148 * CGFloat(covers.count)
        VStack(spacing: 8) {
            Spacer().frame(height: 40)
            row(offset: offset1)
            row(offset: offset2)
            row(offset: offset1)
        }
        .scaleEffect(1.4)
        .blur(radius: 14)
        .onAppear {
            // Core Animation interpola entre estos valores; no se ejecuta código por frame.
            withAnimation(.linear(duration: Double(totalWidth / 25)).repeatForever(autoreverses: false)) {
                offset1 = -totalWidth
            }
            withAnimation(.linear(duration: Double(totalWidth / 25)).repeatForever(autoreverses: false)) {
                offset2 = totalWidth
            }
        }
    }

    private func row(offset: CGFloat) -> some View {
        let doubled = covers + covers
        return HStack(spacing: 8) {
            ForEach(Array(doubled.enumerated()), id: \.offset) { _, url in
                AsyncImage(url: URL(string: url)) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else { Color.bgSurfaceHi }
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .offset(x: offset)
        .frame(height: 140, alignment: .leading)
    }
}

// MARK: - Embedded login

private struct EmbeddedLogin: View {
    let onBack: () -> Void
    let onSwitchToRegister: () -> Void
    @EnvironmentObject var auth: AuthRepository

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPwd: Bool = false
    @State private var error: String? = nil
    @State private var showForgot: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onBack() } label: {
                    Text("← Atrás")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.top, 6)

            Spacer().frame(height: 20)

            Text("Bienvenido de vuelta")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            Spacer().frame(height: 20)

            emailField
            Spacer().frame(height: 10)
            passwordField

            HStack {
                Spacer()
                Button { showForgot = true } label: {
                    Text("¿Olvidaste tu contraseña?")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .padding(.top, 4)

            if let err = error {
                Text(err).font(.system(size: 12)).foregroundStyle(.red).padding(.top, 6)
            }

            Spacer().frame(height: 14)

            Button { Task { await doLogin() } } label: {
                Text(auth.isLoading ? "Entrando..." : "Entrar")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(
                        LinearGradient(colors: [Color.neonPink, Color.neonPurple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(auth.isLoading || email.isEmpty || password.isEmpty)

            Spacer().frame(height: 16)

            Button(action: onSwitchToRegister) {
                Text("¿No tienes cuenta? Crear cuenta")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .alert("Recuperar contraseña", isPresented: $showForgot) {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
            Button("Cancelar", role: .cancel) {}
            Button("Enviar") { Task { await doForgot() } }
        } message: {
            Text("Te enviaremos un enlace para restablecerla.")
        }
    }

    private var emailField: some View {
        TextField("Email", text: $email)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .padding(12)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
    }

    private var passwordField: some View {
        HStack {
            Group {
                if showPwd { TextField("Contraseña", text: $password) }
                else { SecureField("Contraseña", text: $password) }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            Button { showPwd.toggle() } label: {
                Image(systemName: showPwd ? "eye.slash" : "eye")
                    .foregroundStyle(Color.textLow)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
    }

    private func doLogin() async {
        error = nil
        let r = await auth.login(email: email, password: password)
        if case .failure(let e) = r { error = e.errorDescription }
    }

    private func doForgot() async {
        guard email.contains("@") else { error = "Email no válido"; return }
        _ = await auth.forgotPassword(email: email)
        error = "Si esa dirección está registrada, te hemos enviado un email."
    }
}
