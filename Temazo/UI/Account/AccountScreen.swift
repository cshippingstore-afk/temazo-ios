import SwiftUI

struct AccountScreen: View {
    @EnvironmentObject var auth: AuthRepository
    @EnvironmentObject var favorites: FavoritesRepo
    @State private var showRegister = false
    @State private var showSettings = false

    var body: some View {
        Group {
            if let user = auth.currentUser {
                profilePanel(user: user)
            } else {
                LoginPanel(onRegister: { showRegister = true })
            }
        }
        .background(Color.bgRoot)
        .fullScreenCover(isPresented: $showRegister) {
            RegisterScreen { showRegister = false }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen { showSettings = false }
        }
    }

    @ViewBuilder
    private func profilePanel(user: SessionUser) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(Color.neonPink.opacity(0.2)).frame(width: 60, height: 60)
                    Image(systemName: "person.fill").font(.system(size: 28))
                        .foregroundStyle(.neonPink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.email).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text("ID #\(user.id)").font(.system(size: 12)).foregroundStyle(.textLow)
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 22)).foregroundStyle(.textMid)
                }
                Button { Task { await auth.logout() } } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 20)).foregroundStyle(.textMid)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.bgSurface))
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Mis playlists").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text("Próximamente · accede a /mi-cuenta en la web mientras tanto.")
                    .font(.system(size: 12)).foregroundStyle(.textLow)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }
}

private struct LoginPanel: View {
    @EnvironmentObject var auth: AuthRepository
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var error: String? = nil
    let onRegister: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("🎵 Bienvenido a Temazo")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 30)
            Text("Inicia sesión para guardar favoritos y playlists")
                .font(.system(size: 13)).foregroundStyle(.textLow)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
                    .foregroundStyle(.white)

                SecureField("Contraseña", text: $password)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
                    .foregroundStyle(.white)

                if let e = error {
                    Text(e).font(.system(size: 12)).foregroundStyle(.liveRed)
                }

                Button {
                    Task { await doLogin() }
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Iniciar sesión").font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.neonPink))
                    .foregroundStyle(.white)
                }
                .disabled(auth.isLoading)

                Button { onRegister() } label: {
                    Text("Crear cuenta").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.neonCyan)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private func doLogin() async {
        error = nil
        let result = await auth.login(email: email, password: password)
        if case .failure(let e) = result {
            error = e.errorDescription
        }
    }
}
