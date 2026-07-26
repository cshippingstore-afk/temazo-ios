import SwiftUI

/// Admin sheet: fusionar 2 tracks duplicados.
/// El track "source" (el que se abrió el sheet desde su long-press) se hidea y
/// sus favs/plays/playlist_entries se migran al "target" que el user seleccione.
struct AdminMergeTracksSheet: View {
    let sourceTrack: Track
    var onMerged: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var targetIdText: String = ""
    @State private var note: String = ""
    @State private var sending = false
    @State private var errorMsg: String? = nil
    @State private var doneMsg: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Fuente (se ocultará)") {
                    HStack {
                        CoverImage(url: sourceTrack.coverUrl, size: 40, cornerRadius: 4)
                        VStack(alignment: .leading) {
                            Text(sourceTrack.title).lineLimit(1).font(.system(size: 14, weight: .semibold))
                            Text(sourceTrack.artistName ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("ID \(sourceTrack.id)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("ID del track destino (Int)", text: $targetIdText)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Destino (recibirá favs + plays + playlists)")
                } footer: {
                    Text("Pega el ID numérico del track superviviente. Puedes verlo en el sheet Editar metadata de ese track o en la web.")
                }
                Section("Nota (opcional)") {
                    TextField("Ej: mismo master, distinto upload", text: $note)
                }
                if let err = errorMsg { Section { Text(err).foregroundStyle(.red) } }
                if let done = doneMsg { Section { Text(done).foregroundStyle(.green) } }
            }
            .navigationTitle("Fusionar duplicados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fusionar") { Task { await send() } }
                        .disabled(sending || Int(targetIdText) == nil)
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() async {
        guard let tgt = Int(targetIdText), tgt != Int(sourceTrack.id) else {
            errorMsg = "ID inválido"; return
        }
        sending = true; errorMsg = nil; doneMsg = nil
        do {
            let r = try await AdminService.shared.mergeTracks(
                sourceId: Int(sourceTrack.id), targetId: tgt,
                note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note)
            doneMsg = "OK: \(r.migrated.favs) favs, \(r.migrated.plays) plays, \(r.migrated.playlist_entries) playlists migrados"
            onMerged?()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch { errorMsg = error.localizedDescription }
        sending = false
    }
}
