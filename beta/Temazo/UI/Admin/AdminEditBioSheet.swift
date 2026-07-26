import SwiftUI

/// Admin sheet: editar bio_ai de un artista.
struct AdminEditBioSheet: View {
    let artistId: Int
    let artistName: String
    let currentBio: String?
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var sending = false
    @State private var errorMsg: String? = nil

    init(artistId: Int, artistName: String, currentBio: String?, onSaved: (() -> Void)? = nil) {
        self.artistId = artistId; self.artistName = artistName
        self.currentBio = currentBio; self.onSaved = onSaved
        _text = State(initialValue: currentBio ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(artistName), footer: Text("\(text.count) / 4000 caracteres")) {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                }
                if let err = errorMsg { Section { Text(err).foregroundStyle(.red) } }
            }
            .navigationTitle("Editar bio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await send() } }
                        .disabled(sending || text.count > 4000)
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() async {
        sending = true; errorMsg = nil
        do {
            _ = try await AdminService.shared.editArtistBio(artistId: artistId, bio: text)
            onSaved?()
            dismiss()
        } catch { errorMsg = error.localizedDescription }
        sending = false
    }
}
