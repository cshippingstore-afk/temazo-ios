import SwiftUI

/// Sheet para añadir un track a una playlist del usuario, con opción de crear playlist
/// nueva sobre la marcha. Réplica del Android AddToPlaylistSheet.
struct AddToPlaylistSheet: View {
    let trackId: Int64
    let trackTitle: String
    let onDismiss: () -> Void
    let onAdded: (String) -> Void

    @State private var playlists: [Playlist] = []
    @State private var loading = true
    @State private var addingId: Int64? = nil
    @State private var showCreate = false
    @State private var newName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            createRow
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .background(Color.bgRoot)
        .alert("Nueva playlist", isPresented: $showCreate) {
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) { newName = "" }
            Button("Crear y añadir") { createAndAdd() }
        }
        .task { await loadPlaylists() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Añadir a playlist")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)
            Text(trackTitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var createRow: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.neonPink.opacity(0.25))
                    Image(systemName: "plus").foregroundStyle(Color.white)
                }.frame(width: 44, height: 44)
                Text("Nueva playlist")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.neonPink)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView().tint(Color.neonPink).padding(40)
        } else if playlists.isEmpty {
            Text("Aún no tienes playlists")
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(40)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(playlists) { p in
                        playlistRow(p).onTapGesture { addTo(p) }
                    }
                }
            }
            .frame(maxHeight: 380)
        }
    }

    private func playlistRow(_ p: Playlist) -> some View {
        HStack(spacing: 14) {
            cover(p)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.system(size: 14, weight: p.isLikedDefault == true ? .bold : .medium))
                    .foregroundStyle(p.isLikedDefault == true ? Color.neonPink : Color.white)
                    .lineLimit(1)
                Text("\(p.trackCount ?? 0) canciones")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            if addingId == p.id {
                ProgressView().tint(Color.neonPink).frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cover(_ p: Playlist) -> some View {
        if p.isLikedDefault == true {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.91, green: 0.12, blue: 0.39), Color(red: 0.61, green: 0.15, blue: 0.69)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "heart.fill").foregroundStyle(.white).font(.system(size: 22))
            }
            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let url = makeURL(p.displayCover) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { Color.white.opacity(0.05) }
            }
            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            ZStack {
                Color.neonPink.opacity(0.3)
                Image(systemName: "music.note.list").foregroundStyle(.white)
            }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func loadPlaylists() async {
        do {
            let r = try await TemazoAPI.shared.playlists()
            playlists = r.playlists
        } catch {}
        loading = false
    }

    private func addTo(_ p: Playlist) {
        guard addingId == nil else { return }
        addingId = p.id
        Task {
            do {
                let r = try await TemazoAPI.shared.playlistAdd(p.id, trackId: trackId)
                if r.ok {
                    onAdded(p.name)
                }
            } catch {}
            addingId = nil
        }
    }

    private func createAndAdd() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            do {
                let r = try await TemazoAPI.shared.playlistCreate(name: n)
                if r.ok, let pl = r.playlist {
                    let add = try await TemazoAPI.shared.playlistAdd(pl.id, trackId: trackId)
                    if add.ok {
                        onAdded(pl.name)
                    }
                }
            } catch {}
            newName = ""
        }
    }
}
