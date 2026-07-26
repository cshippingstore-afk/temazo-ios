import SwiftUI

/// Botón "⋯" universal para artist/album/playlist. Al tocarlo abre
/// ConfirmationDialog con:
///   - "Reportar problema" (todos los users logueados)
///   - "Ocultar del catálogo" (solo owners admin)
///
/// Uso:
///     EntityOptionsButton(targetType: "artist", targetId: id, targetName: name)
///     EntityOptionsButton(targetType: "album", targetId: id, targetName: "\(name) · \(artist)")
///
/// El menú se adapta al is_admin del user actual: si NO es admin, solo verá
/// "Reportar problema".
struct EntityOptionsButton: View {
    let targetType: String   // "artist" | "album" | "track"
    let targetId: Int
    let targetName: String
    var iconSize: CGFloat = 18
    var iconColor: Color = .white
    var onChanged: (() -> Void)? = nil

    @ObservedObject private var admin = AdminService.shared
    @State private var showDialog = false
    @State private var showReport = false
    @State private var showHideConfirm = false
    @State private var errorText: String? = nil

    var body: some View {
        Button {
            showDialog = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .confirmationDialog(targetName, isPresented: $showDialog, titleVisibility: .visible) {
            Button("Reportar problema", role: .none) { showReport = true }
            if admin.isAdmin {
                Button("Ocultar del catálogo", role: .destructive) { showHideConfirm = true }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(isPresented: $showReport) {
            AdminReportSheet(targetType: targetType, targetId: targetId, targetTitle: targetName)
        }
        .confirmationDialog("¿Ocultar del catálogo?",
                            isPresented: $showHideConfirm, titleVisibility: .visible) {
            Button("Ocultar", role: .destructive) { Task { await hide() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(targetName) dejará de aparecer en búsquedas y listas. Reversible desde el panel admin.")
        }
        .alert("Error", isPresented: .init(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } })
        ) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private func hide() async {
        do {
            _ = try await AdminService.shared.toggleHidden(
                targetType: targetType, targetId: targetId, hidden: true)
            onChanged?()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
