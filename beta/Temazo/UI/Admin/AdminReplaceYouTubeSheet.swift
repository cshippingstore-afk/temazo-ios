import SwiftUI

/// Admin sheet: reemplazar el youtube_id de un track.
struct AdminReplaceYouTubeSheet: View {
    let trackId: Int
    let trackTitle: String
    let currentYouTubeId: String?
    var onSaved: ((_ newId: String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var note: String = ""
    @State private var sending = false
    @State private var errorMsg: String? = nil
    @State private var doneMsg: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Track") {
                    Text(trackTitle).font(.headline)
                    if let cur = currentYouTubeId {
                        HStack {
                            Text("Actual").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(cur).font(.system(.footnote, design: .monospaced))
                        }
                    }
                }

                Section("Nuevo video") {
                    TextField("URL de YouTube o ID (11 chars)", text: $input, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...4)
                    Text("Acepta: https://youtu.be/... · https://youtube.com/watch?v=... · dQw4w9WgXcQ")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Nota (opcional)") {
                    TextField("Ej: versión oficial en HD", text: $note)
                }

                if let err = errorMsg {
                    Section { Text(err).foregroundStyle(.red) }
                }
                if let done = doneMsg {
                    Section { Text(done).foregroundStyle(.green) }
                }
            }
            .navigationTitle("Reemplazar video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await send() } }
                        .disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() async {
        sending = true; errorMsg = nil; doneMsg = nil
        do {
            let r = try await AdminService.shared.replaceYouTube(
                trackId: trackId,
                youtube: input.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
            doneMsg = "Actualizado a \(r.youtube_id)"
            onSaved?(r.youtube_id)
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        sending = false
    }
}
