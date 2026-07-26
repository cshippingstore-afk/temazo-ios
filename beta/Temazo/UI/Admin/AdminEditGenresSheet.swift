import SwiftUI

/// Admin sheet: editar géneros de un artista (multi-select, max 10).
struct AdminEditGenresSheet: View {
    let artistId: Int
    let artistName: String
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var all: [AdminService.GenreInfo] = []
    @State private var selected: Set<Int> = []
    @State private var loading = true
    @State private var sending = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(artistName)) {
                    Text("Seleccionados: \(selected.count)/10").font(.caption).foregroundStyle(.secondary)
                }
                if loading {
                    ProgressView("Cargando géneros…")
                } else {
                    Section("Géneros principales") {
                        ForEach(all.filter { $0.parent_id == nil }) { g in
                            row(g)
                        }
                    }
                    Section("Subgéneros") {
                        ForEach(all.filter { $0.parent_id != nil }) { g in
                            row(g)
                        }
                    }
                }
                if let err = errorMsg { Section { Text(err).foregroundStyle(.red) } }
            }
            .navigationTitle("Géneros artista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await send() } }.disabled(sending)
                }
            }
            .task { await load() }
        }
        .interactiveDismissDisabled(sending)
    }

    private func row(_ g: AdminService.GenreInfo) -> some View {
        Button {
            if selected.contains(g.id) {
                selected.remove(g.id)
            } else if selected.count < 10 {
                selected.insert(g.id)
            }
        } label: {
            HStack {
                Image(systemName: selected.contains(g.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(g.id) ? .tint : Color.secondary)
                Text(g.name)
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func load() async {
        do {
            all = try await AdminService.shared.listGenres()
            loading = false
        } catch {
            errorMsg = error.localizedDescription
            loading = false
        }
    }
    private func send() async {
        sending = true; errorMsg = nil
        do {
            _ = try await AdminService.shared.editArtistGenres(artistId: artistId, genreIds: Array(selected))
            onSaved?()
            dismiss()
        } catch { errorMsg = error.localizedDescription }
        sending = false
    }
}
