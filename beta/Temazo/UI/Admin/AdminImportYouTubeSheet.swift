import SwiftUI

/// Admin sheet: importar un track nuevo desde una URL de YouTube.
struct AdminImportYouTubeSheet: View {
    var onImported: ((_ trackId: Int, _ title: String, _ existed: Bool) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var artistOverride: String = ""
    @State private var albumOverride: String = ""
    @State private var sending = false
    @State private var errorMsg: String? = nil
    @State private var doneMsg: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("URL de YouTube o ID (11 chars)", text: $input, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...4)
                } header: {
                    Text("Video")
                } footer: {
                    Text("Extrae título, artista, portada y duración desde YouTube. Si ya existe en el catálogo, no lo duplica.")
                }

                Section {
                    TextField("Artista (opcional, override)", text: $artistOverride)
                    TextField("Álbum (opcional)", text: $albumOverride)
                } header: {
                    Text("Overrides")
                } footer: {
                    Text("Déjalos vacíos para que auto-detecte desde YouTube.")
                }

                if let err = errorMsg {
                    Section { Text(err).foregroundStyle(.red) }
                }
                if let done = doneMsg {
                    Section { Text(done).foregroundStyle(.green) }
                }
            }
            .navigationTitle("Importar de YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") { Task { await send() } }
                        .disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overlay {
                if sending {
                    ProgressView("Extrayendo metadata…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() async {
        sending = true; errorMsg = nil; doneMsg = nil
        do {
            let r = try await AdminService.shared.importYouTube(
                youtube: input.trimmingCharacters(in: .whitespacesAndNewlines),
                artistName: artistOverride.trimmingCharacters(in: .whitespaces).isEmpty ? nil : artistOverride,
                albumName: albumOverride.trimmingCharacters(in: .whitespaces).isEmpty ? nil : albumOverride)
            let title = r.title ?? "Track"
            doneMsg = r.existed
                ? "Ya existía: \(title) (id \(r.track_id))"
                : "Importado: \(title) (id \(r.track_id))"
            onImported?(r.track_id, title, r.existed)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        sending = false
    }
}
