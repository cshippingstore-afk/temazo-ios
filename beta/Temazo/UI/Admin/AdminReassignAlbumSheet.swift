import SwiftUI

/// Admin sheet: cambiar el álbum de un track.
struct AdminReassignAlbumSheet: View {
    let trackId: Int
    let trackTitle: String
    let currentAlbumName: String?
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var albumIdText: String = ""
    @State private var removeAlbum: Bool = false
    @State private var sending = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Track") {
                    Text(trackTitle).font(.headline)
                    if let cur = currentAlbumName {
                        HStack { Text("Álbum actual").foregroundStyle(.secondary); Spacer(); Text(cur).lineLimit(1) }
                    } else {
                        Text("Sin álbum asignado").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Quitar del álbum (dejar sin asignar)", isOn: $removeAlbum)
                    if !removeAlbum {
                        TextField("ID del álbum destino", text: $albumIdText)
                            .keyboardType(.numberPad)
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text("Cambiar a")
                } footer: {
                    Text("Puedes ver el ID del álbum en la URL de la web temazo.es/album/... o en la pantalla de admin del álbum.")
                }
                if let err = errorMsg { Section { Text(err).foregroundStyle(.red) } }
            }
            .navigationTitle("Reasignar álbum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await send() } }
                        .disabled(sending || (!removeAlbum && Int(albumIdText) == nil))
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() async {
        sending = true; errorMsg = nil
        do {
            let newId: Int? = removeAlbum ? nil : Int(albumIdText)
            _ = try await AdminService.shared.reassignAlbum(trackId: trackId, albumId: newId)
            onSaved?()
            dismiss()
        } catch { errorMsg = error.localizedDescription }
        sending = false
    }
}
