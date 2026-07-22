import SwiftUI

/// Pantalla de bienvenida — clon visual 1:1 del Android v1.55+
///  · Background: vertical gradient #1a0a2e → #0d0517 → black
///  · CoverWall blurred + scrollable auto (2 filas alternando dirección)
///  · Overlay gradient encima para contraste
///  · Logo Temazo 88pt + título 26sp black + subtítulo 14sp
///  · 3 botones (registro filled púrpura, Google outlined, email outlined)
struct WelcomeScreen: View {
    @EnvironmentObject var auth: AuthRepository

    enum Mode { case welcome, login, register }
    @State private var mode: Mode = .welcome
    @State private var covers: [String] = []
    @State private var busy: Bool = false
    @State private var errorText: String? = nil

    // Color principal — rosa neón sólido como Android (no gradient, no púrpura MD3)
    // Android usa colorScheme.primary del tema oscuro Temazo = neonPink
    private let mdPrimary = Color(red: 1.00, green: 0.18, blue: 0.58)  // #FF2E93 neonPink

    var body: some View {
        ZStack {
            // 1) Fondo gradiente base
            LinearGradient(colors: [Color(hex: 0x1a0a2e), Color(hex: 0x0d0517), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // 2) Cover wall sólo en welcome
            if mode == .welcome && covers.count >= 6 {
                CoverWallBackground(covers: covers)
                    .ignoresSafeArea()
                // Overlay para garantizar contraste sobre la pared
                LinearGradient(colors: [
                    Color(hex: 0x1a0a2e).opacity(0.55),
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.95)
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            }

            // 3) Contenido según modo
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
                var urls = Array(Set(r.tracks.compactMap { $0.coverUrl }))
                if urls.count < 6 {
                    let r2 = try await TemazoAPI.shared.trendingByGenre("pop", limit: 30)
                    urls.append(contentsOf: r2.tracks.compactMap { $0.coverUrl })
                    urls = Array(Set(urls))
                }
                covers = urls
            } catch {}
        }
    }

    // MARK: - Welcome body (mismo layout y proporciones que Android)

    private var welcomeBody: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Spacer weight 0.4 — empuja el bloque del logo hacia el medio-arriba
                Spacer().frame(height: geo.size.height * 0.10)

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

                Spacer().frame(height: 10)

                Text("Millones de canciones · Playlists con amigos · Sin límites")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                // Spacer weight(1f) — empuja los botones al fondo
                Spacer(minLength: 16)

                if let err = errorText {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }

                // Botón principal — filled MD3 primary (púrpura sólido como Android)
                Button { mode = .register } label: {
                    Text("Crea tu cuenta gratis")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(mdPrimary)
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(busy)

                Spacer().frame(height: 10)

                // Google — OutlinedButton (borde blanco, G en azul Google)
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
    }

    private func tryGoogle() {
        // Google Sign-In SDK pendiente de integrar en iOS — muestra mensaje
        errorText = "Google Sign-In aún no está configurado en iOS. Usa email."
    }
}

// MARK: - CoverWall background — 2 filas auto-scroll alternas (idéntico al Android)

private struct CoverWallBackground: View {
    let covers: [String]
    @State private var startAnimation: Bool = false

    var body: some View {
        let cellW: CGFloat = 140
        let gap: CGFloat = 8
        let doubled = covers + covers + covers   // triple para wrap suave
        let rowWidth: CGFloat = CGFloat(doubled.count) * (cellW + gap)
        let halfWidth: CGFloat = rowWidth / 2

        VStack(spacing: gap) {
            row(items: doubled, gap: gap, cellW: cellW,
                offset: startAnimation ? -halfWidth : 0,
                duration: Double(halfWidth / 25))
            row(items: doubled.reversed(), gap: gap, cellW: cellW,
                offset: startAnimation ? halfWidth : 0,
                duration: Double(halfWidth / 25))
            row(items: doubled, gap: gap, cellW: cellW,
                offset: startAnimation ? -halfWidth : 0,
                duration: Double(halfWidth / 25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .scaleEffect(1.4)
        .blur(radius: 14)
        .onAppear {
            // Pequeño delay para que SwiftUI mida y luego arranque la animación infinita
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startAnimation = true
            }
        }
    }

    private func row(items: [String], gap: CGFloat, cellW: CGFloat,
                     offset: CGFloat, duration: Double) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, url in
                AsyncImage(url: URL(string: url)) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else { Color.white.opacity(0.06) }
                }
                .frame(width: cellW, height: cellW)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .offset(x: offset)
        .animation(
            .linear(duration: duration).repeatForever(autoreverses: false),
            value: offset
        )
        .frame(height: cellW, alignment: .leading)
    }
}

// MARK: - Embedded login (sin cambios visuales — back button arriba)

private struct EmbeddedLogin: View {
    let onBack: () -> Void
    let onSwitchToRegister: () -> Void
    @EnvironmentObject var auth: AuthRepository

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPwd: Bool = false
    @State private var error: String? = nil
    @State private var showForgot: Bool = false

    private let mdPrimary = Color(red: 0.40, green: 0.31, blue: 0.64)

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
                    .background(mdPrimary)
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
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15)))
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
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15)))
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
