import SwiftUI

/// Pantalla de bienvenida para usuarios no logueados. Login con email/password +
/// link a registro. Forgot password en modal.
/// Aparece como gate fullScreenCover desde MainScreen mientras `auth.currentUser == nil`.
struct WelcomeScreen: View {
    @EnvironmentObject var auth: AuthRepository

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPwd: Bool = false
    @State private var error: String? = nil
    @State private var showRegister: Bool = false
    @State private var showForgot: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1a0a2e), Color(hex: 0x0a0a1a)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Spacer().frame(height: 50)

                    Text("🎵 Temazo")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(
                            LinearGradient(colors: [Color.neonPink, Color.neonCyan],
                                           startPoint: .leading, endPoint: .trailing)
                        )

                    Text("Tu música. Tu top. Tu mundo.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textMid)
                        .padding(.bottom, 14)

                    emailField
                    passwordField

                    if let e = error {
                        Text(e).font(.system(size: 12)).foregroundStyle(.red)
                    }

                    Button { showForgot = true } label: {
                        Text("¿Olvidaste tu contraseña?")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.neonCyan)
                    }

                    loginButton

                    HStack(spacing: 6) {
                        Text("¿Aún no tienes cuenta?")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textMid)
                        Button { showRegister = true } label: {
                            Text("Regístrate")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.neonPink)
                        }
                    }
                    .padding(.top, 8)

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .fullScreenCover(isPresented: $showRegister) {
            RegisterScreen { showRegister = false }
        }
        .alert("Recuperar contraseña", isPresented: $showForgot) {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
            Button("Cancelar", role: .cancel) {}
            Button("Enviar") { Task { await doForgot() } }
        } message: {
            Text("Te enviaremos un enlace a \(email.isEmpty ? "tu email" : email)")
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
                if showPwd {
                    TextField("Contraseña", text: $password)
                } else {
                    SecureField("Contraseña", text: $password)
                }
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

    private var loginButton: some View {
        Button { Task { await doLogin() } } label: {
            Group {
                if auth.isLoading { ProgressView().tint(.white) }
                else { Text("Entrar").font(.system(size: 15, weight: .bold)) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Color.neonPink, Color.neonPurple],
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        }
        .disabled(auth.isLoading)
        .padding(.top, 4)
    }

    private func doLogin() async {
        error = nil
        let r = await auth.login(email: email, password: password)
        if case .failure(let e) = r { error = e.errorDescription }
    }

    private func doForgot() async {
        guard !email.isEmpty else { error = "Introduce tu email"; return }
        let r = await auth.forgotPassword(email: email)
        switch r {
        case .success: error = "Te hemos enviado un email"
        case .failure(let e): error = e.errorDescription
        }
    }
}
