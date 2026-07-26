import SwiftUI

/// Admin sheet: importar todos los tracks de una playlist YouTube.
struct AdminImportPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url: String = ""
    @State private var sending = false
    @State private var errorMsg: String? = nil
    @State private var result: AdminService.ImportPlaylistResponse? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://youtube.com/playlist?list=...", text: $url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...4)
                } header: {
                    Text("URL de playlist YouTube")
                } footer: {
                    Text("El sistema extraerá todos los IDs y los importará en background con pacing 2s/track (~1-2 min por cada 30 canciones). Puedes cerrar y volver más tarde.")
                }
                if let r = result {
                    Section("Resultado") {
                        Text("Task: \(r.task_id)").font(.system(.caption, design: .monospaced))
                        Text("Total tracks: \(r.total_tracks)").font(.headline)
                        Text("Log: \(r.log_file)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                if let err = errorMsg { Section { Text(err).foregroundStyle(.red) } }
            }
            .navigationTitle("Importar playlist YT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "…" : "Importar") { Task { await send() } }
                        .disabled(sending || url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() async {
        sending = true; errorMsg = nil; result = nil
        do {
            result = try await AdminService.shared.importYouTubePlaylist(
                url: url.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { errorMsg = error.localizedDescription }
        sending = false
    }
}
