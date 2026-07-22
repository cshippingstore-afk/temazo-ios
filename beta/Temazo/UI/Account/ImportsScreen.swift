import SwiftUI

/// Solicitudes de importación de artistas/canciones que faltan en Temazo.
/// Equivalente del Android `ImportsScreen.kt`.
struct ImportsScreen: View {
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    /// Callback cuando el usuario abre un import 'done' con url (ruta tipo "/<artist>" o "/<artist>/<song>").
    let onOpenUrl: (String) -> Void

    @EnvironmentObject var player: Player
    @ObservedObject private var notifs = NotificationsRepo.shared

    @State private var mine: [ImportItem] = []
    @State private var top: [ImportTop] = []
    @State private var loading: Bool = true
    @State private var error: String? = nil
    @State private var showCreate: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header custom: tiene action de "Añadir" además del back
            TemazoTopBar(
                isPlaying: player.state.isPlaying,
                unreadNotifs: notifs.unread,
                onAvatarClick: onAvatarClick,
                onBellClick: onBellClick,
                onEventsClick: onEventsClick,
                onNewsClick: onNewsClick
            )
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Text("Solicitudes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if loading {
                Spacer()
                ProgressView().tint(Color.neonPink)
                Spacer()
            } else if let e = error {
                Spacer()
                Text(e).foregroundStyle(.white.opacity(0.7))
                Spacer()
            } else if mine.isEmpty && top.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !mine.isEmpty {
                            Text("Mis solicitudes")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.top, 4)
                            ForEach(mine, id: \.id) { req in
                                importRow(req)
                            }
                        }
                        if !top.isEmpty {
                            Spacer().frame(height: 12)
                            Text("Más pedidas por la comunidad")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            ForEach(Array(top.enumerated()), id: \.offset) { _, t in
                                topRow(t)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showCreate) {
            NewImportSheet { type, artist, track in
                showCreate = false
                Task { await submitImport(type: type, artist: artist, track: track) }
            } onCancel: {
                showCreate = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 64)
            Text("Sin solicitudes todavía")
                .foregroundStyle(.white.opacity(0.5))
            Text("Solicita un artista o canción que falte en Temazo")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rows

    private func importRow(_ req: ImportItem) -> some View {
        let canOpen = req.status == "done" && !(req.url?.isEmpty ?? true)
        let (label, color) = statusOf(req.status)
        return Button {
            if canOpen, let u = req.url { onOpenUrl(u) }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.neonPink.opacity(0.15))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: req.type == "artist" ? "mic.fill" : "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.neonPink)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(type: req.type, artist: req.artist_name, track: req.track_title))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(req.type == "artist" ? "Artista" : "Canción")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                        if req.request_count > 1 {
                            Text("· \(req.request_count) solicitudes")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                Spacer()
                statusChip(label: label, color: color)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
    }

    private func topRow(_ t: ImportTop) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.neonPink.opacity(0.10))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: t.type == "artist" ? "mic.fill" : "music.note")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.neonPink)
                )
            Text(displayName(type: t.type, artist: t.artist_name, track: t.track_title))
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text("\(t.request_count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.neonPink)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func statusChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func displayName(type: String, artist: String?, track: String?) -> String {
        if type == "track", let t = track, !t.isEmpty {
            return "\(t) — \(artist ?? "")"
        }
        return artist ?? ""
    }

    private func statusOf(_ s: String) -> (String, Color) {
        switch s {
        case "pending":   return ("En cola", Color(red: 0.65, green: 0.71, blue: 0.99))
        case "searching": return ("Buscando", Color(red: 0.98, green: 0.75, blue: 0.14))
        case "importing": return ("Importando", Color(red: 0.98, green: 0.75, blue: 0.14))
        case "done":      return ("Listo", Color(red: 0.53, green: 0.94, blue: 0.67))
        case "rejected":  return ("No disponible", Color(red: 0.99, green: 0.65, blue: 0.65))
        case "failed":    return ("Error", Color(red: 0.99, green: 0.65, blue: 0.65))
        default:          return (s, Color.white.opacity(0.6))
        }
    }

    // MARK: - Actions

    private func reload() async {
        loading = true
        do {
            let r = try await TemazoAPI.shared.myImports()
            mine = r.mine
            top = r.top
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func submitImport(type: String, artist: String, track: String) async {
        do {
            let r = try await TemazoAPI.shared.requestImport(
                type: type,
                artistName: artist,
                trackTitle: type == "track" ? track : nil
            )
            if r.ok == true, let url = r.redirect_url {
                onOpenUrl(url)
            } else {
                await reload()
            }
        } catch {
            await reload()
        }
    }
}

// MARK: - NewImportSheet

private struct NewImportSheet: View {
    let onSubmit: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var type: String = "artist"
    @State private var artist: String = ""
    @State private var track: String = ""

    private var canSubmit: Bool {
        let a = artist.trimmingCharacters(in: .whitespaces)
        let t = track.trimmingCharacters(in: .whitespaces)
        if a.count < 2 || a.count > 100 { return false }
        if type == "track" {
            return t.count >= 2 && t.count <= 100
        }
        return true
    }

    var body: some View {
        ZStack {
            Color(red: 0.102, green: 0.094, blue: 0.145).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                Text("Solicitar importación")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    typeChip(label: "Artista", icon: "mic.fill", selected: type == "artist") { type = "artist" }
                    typeChip(label: "Canción", icon: "music.note", selected: type == "track") { type = "track" }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nombre del artista")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("", text: $artist, prompt: Text("Artista").foregroundColor(.white.opacity(0.4)))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }

                if type == "track" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Título de la canción")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                        TextField("", text: $track, prompt: Text("Canción").foregroundColor(.white.opacity(0.4)))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancelar")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    Spacer()
                    Button {
                        onSubmit(type, artist.trimmingCharacters(in: .whitespaces), track.trimmingCharacters(in: .whitespaces))
                    } label: {
                        Text("Enviar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(canSubmit ? Color.neonPink : Color.white.opacity(0.15)))
                    }
                    .disabled(!canSubmit)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
        .presentationDetents([.medium])
    }

    private func typeChip(label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 13, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? .white : Color.white.opacity(0.7))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                Capsule().fill(selected ? Color.neonPink : Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }
}
