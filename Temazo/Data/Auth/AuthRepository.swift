import Foundation

@MainActor
final class AuthRepository: ObservableObject {
    static let shared = AuthRepository()

    @Published var currentUser: SessionUser? = nil
    @Published var isLoading: Bool = false

    private init() {}

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
