import SwiftUI

/// Admin sheet: editar metadata de un track (título, artista, año, portada).
struct AdminEditMetaSheet: View {
    let trackId: Int
    let originalTitle: String
    let originalArtist: String
    let originalReleaseDate: String?
    let originalCoverURL: String?
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @State private var releaseDate: String
    @State private var coverURL: String
    @State private var sending = false
    @State private var errorMsg: String? = nil

    init(trackId: Int, originalTitle: String, originalArtist: String,
         originalReleaseDate: String? = nil, originalCoverURL: String? = nil,
         onSaved: (() -> Void)? = nil) {
        self.trackId = trackId
        self.originalTitle = originalTitle
        self.originalArtist = originalArtist
        self.originalReleaseDate = originalReleaseDate
        self.originalCoverURL = originalCoverURL
        self.onSaved = onSaved
        _title = State(initialValue: originalTitle)
        _artist = State(initialValue: originalArtist)
        _releaseDate = State(initialValue: originalReleaseDate ?? "")
        _coverURL = State(initialValue: originalCoverURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Título") {
                    TextField("Título", text: $title)
                }
                Section("Artista") {
                    TextField("Artista", text: $artist)
                }
                Section("Fecha de lanzamiento") {
                    TextField("YYYY-MM-DD o YYYY", text: $releaseDate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("URL de portada") {
                    TextField("https://...", text: $coverURL, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                }
                if let err = errorMsg {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Editar metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await send() } }
                        .disabled(sending || !hasChanges)
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private var hasChanges: Bool {
        title != originalTitle
            || artist != originalArtist
            || releaseDate != (originalReleaseDate ?? "")
            || coverURL != (originalCoverURL ?? "")
    }

    private func send() async {
        sending = true; errorMsg = nil
        do {
            _ = try await AdminService.shared.editMeta(
                trackId: trackId,
                title: title != originalTitle ? title : nil,
                artistName: artist != originalArtist ? artist : nil,
                releaseDate: releaseDate != (originalReleaseDate ?? "") ? releaseDate : nil,
                coverURL: coverURL != (originalCoverURL ?? "") ? coverURL : nil)
            onSaved?()
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        sending = false
    }
}
