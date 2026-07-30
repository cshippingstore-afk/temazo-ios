import SwiftUI

/// BETA v1.2.33 — Paridad con web y Android v1.0.5+.
/// Muestra un card llamativo "¿No encuentras a tu artista? — Solicitar →"
/// que envía POST a /api/request_import.php.
///
/// Modos:
///   - showHeader=true (empty state): incluye texto grande "No se encontraron
///     resultados para <query>" y la card debajo, centrada.
///   - showHeader=false (inline al final de una lista de resultados): solo la card.
///
/// Estados: idle → sending → sent | alreadyExists | alreadyRequested |
///          rateLimited | needLogin | error.
struct NoResultsWithImportCta: View {
    let query: String
    var showHeader: Bool = true

    @State private var status: ImportStatus = .idle

    enum ImportStatus: Equatable {
        case idle
        case sending
        case sent
        case alreadyExists(url: String?)
        case alreadyRequested
        case rateLimited
        case needLogin
        case error(String)
    }

    var body: some View {
        VStack(spacing: 12) {
            if showHeader {
                Spacer().frame(height: 24)
                Text("No se encontraron resultados para")
                    .foregroundStyle(Color.white.opacity(0.55))
                    .font(.system(size: 14))
                Text("\"\(query)\"")
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(2).multilineTextAlignment(.center)
                Spacer().frame(height: 12)
            }

            // Card CTA
            HStack(spacing: 12) {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.906, green: 0.298, blue: 0.545),
                                            Color(red: 0.659, green: 0.333, blue: 0.969)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                    Image(systemName: "music.note")
                        .foregroundStyle(.white)
                        .font(.system(size: 20, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("¿No encuentras a tu artista?")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text("Trae \"\(query)\" a Temazo")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.65)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                switch status {
                case .idle, .error:
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Solicitar")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [Color(red: 0.906, green: 0.298, blue: 0.545),
                                                     Color(red: 0.659, green: 0.333, blue: 0.969)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                case .sending:
                    ProgressView().tint(.white).scaleEffect(0.9)
                case .sent, .alreadyExists, .alreadyRequested:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 22))
                case .rateLimited, .needLogin:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .font(.system(size: 22))
                }
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Color(red: 0.165, green: 0.075, blue: 0.251),
                                        Color(red: 0.102, green: 0.039, blue: 0.180)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.906, green: 0.298, blue: 0.545).opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)

            // Feedback
            switch status {
            case .sent:
                statusText("Solicitud enviada. Te avisamos cuando esté lista.", color: .green)
            case .alreadyExists:
                statusText("Ya existe en el catálogo.", color: .cyan)
            case .alreadyRequested:
                statusText("Ya lo solicitaste antes — está en la cola.", color: .cyan)
            case .rateLimited:
                statusText("Demasiadas solicitudes hoy. Espera unas horas.", color: .orange)
            case .needLogin:
                statusText("Inicia sesión para solicitar.", color: .orange)
            case .error(let msg):
                statusText(msg, color: .red)
            default: EmptyView()
            }

            if showHeader { Spacer() }
        }
    }

    @ViewBuilder
    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }

    private func submit() async {
        status = .sending
        do {
            let r = try await TemazoAPI.shared.requestImport(
                type: "artist",
                artistName: query.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            switch (r.status, r.error) {
            case ("pending", _):            status = .sent
            case ("already_exists", _):     status = .alreadyExists(url: r.redirect_url)
            case ("already_requested", _):  status = .alreadyRequested
            case ("rate_limited", _):       status = .rateLimited
            case (_, "login_required"):     status = .needLogin
            case (_, .some(let e)):         status = .error(r.message ?? e)
            default:                        status = .sent
            }
        } catch {
            let ns = error as NSError
            if ns.code == 401 {
                status = .needLogin
            } else {
                status = .error(error.localizedDescription)
            }
        }
    }
}
