import Foundation

@MainActor
final class AuthRepository: ObservableObject {
    static let shared = AuthRepository()

    @Published var currentUser: SessionUser? = nil
    @Published var isLoading: Bool = false

    private init() {}

    func refreshSession() async {
        do {
            let resp = try await TemazoAPI.shared.session()
            currentUser = resp.user
        } catch {
            print("[Auth] session refresh failed: \(error)")
        }
    }

    func login(email: String, password: String) async -> Result<Void, AuthError> {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await TemazoAPI.shared.login(email: email, password: password)
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
                  gender: String, countryCode: String) async -> Result<Void, AuthError> {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await TemazoAPI.shared.register(
                email: email, password: password, birthDate: birthDate,
                gender: gender, countryCode: countryCode)
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
