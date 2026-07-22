import Foundation

@MainActor
final class AuthRepository: ObservableObject {
    static let shared = AuthRepository()

    @Published var currentUser: SessionUser? = nil
    @Published var isLoading: Bool = false
    /// URL absoluta del avatar del user logueado. Se actualiza desde AccountScreen
    /// (loadProfile + avatarUpload) y desde EditProfileScreen. La consume el TopBar
    /// para refrescar al instante el botón avatar sin tener que recargar AccountScreen.
    /// Equivalente al `StateFlow<String?> avatarUrl` de Android AuthRepository.
    @Published var avatarUrl: String? = nil

    private static let userDefaultsKey = "temazo_session_user"
    private static let avatarUrlKey = "temazo_session_avatar_url"

    private init() {
        // Restaurar usuario del disco INMEDIATAMENTE — así la UI nunca arranca
        // mostrando WelcomeScreen mientras refreshSession() está en vuelo.
        // El user real se valida en background y solo se reemplaza si cambió;
        // nunca se borra por error de red (sesión firme).
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let user = try? JSONDecoder().decode(SessionUser.self, from: data) {
            self.currentUser = user
        }
        // Restaurar avatar persistido para que el TopBar arranque con la foto
        // correcta antes de que loadProfile() llegue del server.
        self.avatarUrl = UserDefaults.standard.string(forKey: Self.avatarUrlKey)
    }

    /// Punto único de actualización del avatar — lo llaman AccountScreen y
    /// EditProfileScreen cada vez que cargan profile o suben foto nueva.
    /// Refresca todo lo que observe `auth.avatarUrl` (TopBar, etc.) y persiste
    /// para próximos arranques. `nil` borra (delete avatar).
    func setAvatarUrl(_ url: String?) {
        avatarUrl = url
        if let url, !url.isEmpty {
            UserDefaults.standard.set(url, forKey: Self.avatarUrlKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.avatarUrlKey)
        }
    }

    private func persistCurrentUser() {
        if let u = currentUser, let data = try? JSONEncoder().encode(u) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        }
    }

    /// Sesión FIRME: si tenemos cookies persistidas, mantenemos al usuario logueado
    /// aunque el server no responda (modo avión, error puntual). Solo se borra el user
    /// si el server devuelve user=null explícitamente Y NO había cookies guardadas.
    /// Regla absoluta: el usuario NO sale de su sesión salvo que desinstale la app o
    /// pulse "Cerrar sesión" desde Ajustes.
    func refreshSession() async {
        do {
            let resp = try await TemazoAPI.shared.session()
            if let u = resp.user {
                currentUser = u
                persistCurrentUser()
            }
            // Si user=null pero teníamos cookies persistidas, no tocamos currentUser:
            // el server pudo invalidar sesión por timeout pero seguimos optimistas.
        } catch {
            print("[Auth] session refresh failed (offline?): \(error)")
            // No borramos currentUser: red fallida no es razón para echar al usuario.
        }
    }

    /// Login con Google ID token (Sign-In with Google).
    func loginWithGoogleIdToken(_ idToken: String) async -> Result<Void, AuthError> {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await TemazoAPI.shared.loginWithGoogleIdToken(idToken)
            if resp.ok == true, let u = resp.user {
                currentUser = u
                persistCurrentUser()
                TemazoAPI.shared.persistCookies()
                return .success(())
            }
            return .failure(.message(localizeError(resp.error) ?? resp.msg ?? "Google login error"))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    /// Forgot password: dispara email de recuperación.
    func forgotPassword(email: String) async -> Result<Void, AuthError> {
        do {
            let resp = try await TemazoAPI.shared.forgotPassword(email: email)
            if resp.ok == true { return .success(()) }
            return .failure(.message(localizeError(resp.error) ?? "No se pudo enviar"))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    func login(email: String, password: String, remember: Bool = true) async -> Result<Void, AuthError> {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await TemazoAPI.shared.login(email: email, password: password, remember: remember)
            if resp.ok == true, let u = resp.user {
                currentUser = u
                persistCurrentUser()
                TemazoAPI.shared.persistCookies()  // mantener login entre lanzamientos
                return .success(())
            }
            return .failure(.message(localizeError(resp.error) ?? resp.msg ?? "Login error"))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    func register(email: String, password: String, birthDate: String,
                  gender: String, countryCode: String, remember: Bool = true) async -> Result<Void, AuthError> {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await TemazoAPI.shared.register(
                email: email, password: password, birthDate: birthDate,
                gender: gender, countryCode: countryCode, remember: remember)
            if resp.ok == true, let u = resp.user {
                currentUser = u
                persistCurrentUser()
                TemazoAPI.shared.persistCookies()
                return .success(())
            }
            return .failure(.message(localizeError(resp.error) ?? resp.msg ?? "Register error"))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    func logout() async {
        _ = try? await TemazoAPI.shared.logout()
        clearCookies()
        TemazoAPI.shared.clearPersistedCookies()
        currentUser = nil
        persistCurrentUser()  // borra del disco
        setAvatarUrl(nil)     // limpia avatar persistido para próxima sesión
    }

    private func clearCookies() {
        if let cs = HTTPCookieStorage.shared.cookies {
            for c in cs { HTTPCookieStorage.shared.deleteCookie(c) }
        }
        TemazoAPI.shared.csrfToken = nil
    }

    private func localizeError(_ code: String?) -> String? {
        switch code {
        case "email_invalid":      return "Email no válido"
        case "password_weak":      return "Contraseña débil. Mín 8 caracteres con un número"
        case "birth_date_invalid": return "Fecha de nacimiento no válida"
        case "gender_invalid":     return "Selecciona un género"
        case "country_invalid":    return "Selecciona un país"
        case "captcha_failed":     return "Verificación fallida. Intenta de nuevo"
        case "rate_limit":         return "Demasiados intentos. Espera un momento"
        case "email_exists":       return "Ya existe una cuenta con ese email"
        case "invalid_credentials": return "Email o contraseña incorrectos"
        default: return nil
        }
    }
}

enum AuthError: LocalizedError, Equatable {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}
