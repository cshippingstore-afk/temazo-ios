import SwiftUI

/// Sheet para reportar problema con track/artist/album.
/// **Accesible por CUALQUIER user logueado** (no requiere admin).
/// Los admins ven la queue en la pestaña Admin.
struct AdminReportSheet: View {
    let targetType: String   // "track" | "artist" | "album"
    let targetId: Int
    let targetTitle: String  // texto humano ("Despacito · Luis Fonsi")

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: Reason? = nil
    @State private var note: String = ""
    @State private var sending = false
    @State private var errorMsg: String? = nil
    @State private var doneMsg: String? = nil

    enum Reason: String, CaseIterable, Identifiable {
        case noReproduce   = "no_reproduce"
        case soundsBad     = "sounds_bad"
        case wrongVersion  = "wrong_version"
        case badCover      = "bad_cover"
        case badLyricsSync = "bad_lyrics_sync"
        case wrongTitle    = "wrong_title"
        case wrongArtist   = "wrong_artist"
        case wrongAlbum    = "wrong_album"
        case offensive     = "offensive"
        case other         = "other"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .noReproduce:   return "No reproduce"
            case .soundsBad:     return "Suena mal / calidad baja"
            case .wrongVersion:  return "Versión equivocada"
            case .badCover:      return "Portada mala"
            case .badLyricsSync: return "Letra desincronizada"
            case .wrongTitle:    return "Título incorrecto"
            case .wrongArtist:   return "Artista incorrecto"
            case .wrongAlbum:    return "Álbum incorrecto"
            case .offensive:     return "Contenido ofensivo"
            case .other:         return "Otro problema"
            }
        }
        var systemImage: String {
            switch self {
            case .noReproduce:   return "pause.circle"
            case .soundsBad:     return "waveform.badge.exclamationmark"
            case .wrongVersion:  return "arrow.left.arrow.right.circle"
            case .badCover:      return "photo.badge.exclamationmark"
            case .badLyricsSync: return "text.badge.xmark"
            case .wrongTitle:    return "textformat"
            case .wrongArtist:   return "person.crop.circle.badge.questionmark"
            case .wrongAlbum:    return "square.stack.3d.up.badge.a"
            case .offensive:     return "exclamationmark.triangle"
            case .other:         return "questionmark.circle"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(targetTitle).font(.headline)
                } header: {
                    Text("Reportar problema")
                }

                Section("Motivo") {
                    ForEach(Reason.allCases) { r in
                        Button {
                            selectedReason = r
                        } label: {
                            HStack {
                                Image(systemName: r.systemImage).frame(width: 28)
                                Text(r.label)
                                Spacer()
                                if selectedReason == r {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Nota opcional") {
                    TextEditor(text: $note)
                        .frame(minHeight: 60)
                }

                if let err = errorMsg {
                    Section { Text(err).foregroundStyle(.red) }
                }
                if let done = doneMsg {
                    Section { Text(done).foregroundStyle(.green) }
                }
            }
            .navigationTitle("Reportar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enviar") { Task { await send() } }
                        .disabled(selectedReason == nil || sending)
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() async {
        guard let reason = selectedReason else { return }
        sending = true; errorMsg = nil; doneMsg = nil
        do {
            _ = try await AdminService.shared.report(
                targetType: targetType, targetId: targetId,
                reason: reason.rawValue,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
            doneMsg = "Reporte enviado. Gracias."
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        sending = false
    }
}
