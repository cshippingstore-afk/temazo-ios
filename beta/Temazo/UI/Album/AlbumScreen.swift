import SwiftUI

/// Pantalla de álbum — réplica visual del Android AlbumScreen.
/// Header (cover 220dp + nombre + artista clickable + meta) → Botón "Reproducir álbum"
/// → lista numerada de tracks.
struct AlbumScreen: View {
    let albumId: Int64?
    let albumSlug: String?
    let onBack: () -> Void
    let onArtistClick: (Int64) -> Void
    let onPlayTracks: ([Track], Int) -> Void

    @State private var album: Album? = nil
    @State private var artist: ArtistMini? = nil
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var error: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56)
                    if loading {
                        ProgressView().tint(Color.neonPink).padding(40)
                    } else if let e = error {
                        Text(e).foregroundStyle(Color.white.opacity(0.7)).padding(40)
                    } else if let a = album {
                        headerView(a)
                        if !tracks.isEmpty {
                            playButton
                            downloadAlbumButton
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                                trackRow(t, idx: idx + 1)
                                    .onTapGesture { onPlayTracks(tracks, idx) }
                            }
                        }
                    }
                    Spacer().frame(height: 30)
                }
            }
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(10)
                }
                Text(album?.name ?? "Álbum")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer()
                if loading {
                    ProgressView().tint(Color.neonPink).padding(.trailing, 12)
                }
            }
            .frame(height: 50)
            .padding(.horizontal, 4)
        }
        .task { await load() }
    }

    private func headerView(_ a: Album) -> some View {
        VStack(spacing: 12) {
            ZStack {
                if let u = makeURL(a.cover ?? a.imageLarge) {
                    AsyncImage(url: u) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else { Color.white.opacity(0.05) }
                    }
                } else { Color.white.opacity(0.05) }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(a.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if let ar = artist {
                Button { onArtistClick(ar.id) } label: {
                    Text(ar.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.neonPink)
                }
            }
            let meta = [
                a.releaseDate?.prefix(4).description.nilIfEmpty,
                a.albumType?.capitalized.nilIfEmpty,
                a.totalTracks.map { "\($0) canciones" }
            ].compactMap { $0 }
            if !meta.isEmpty {
                Text(meta.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var playButton: some View {
        Button { onPlayTracks(tracks, 0) } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 16))
                Text("Reproducir álbum").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.neonPink)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// BETA v1.1: descarga todos los tracks del álbum en background.
    /// Visualmente estado: hasDownloads (todos ya descargados) → check verde
    /// idle → botón "Descargar álbum" (icono ↓ + texto)
    @ViewBuilder
    private var downloadAlbumButton: some View {
        let ytIds = tracks.compactMap { $0.youtubeId }.filter { !$0.isEmpty }
        let allDownloaded = !ytIds.isEmpty
            && ytIds.allSatisfy { OfflineLibrary.shared.isDownloaded($0) }
        Button {
            if !allDownloaded {
                _ = DownloadManager.shared.downloadAll(tracks)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: allDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 15))
                Text(allDownloaded ? "Álbum descargado" : "Descargar álbum")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(allDownloaded ? Color.green : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(allDownloaded
                        ? Color.green.opacity(0.15)
                        : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .disabled(allDownloaded)
    }

    private func trackRow(_ t: Track, idx: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(idx)")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white).lineLimit(1)
                if let n = t.artistName, !n.isEmpty {
                    Text(n).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer()
            Text(t.displayDuration).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func load() async {
        loading = true
        do {
            let r = try await TemazoAPI.shared.album(id: albumId, slug: albumSlug)
            if r.success, let a = r.album {
                album = a
                artist = r.artist
                tracks = r.tracks.filter { !($0.youtubeId ?? "").isEmpty }
                error = nil
            } else {
                error = r.error ?? "Álbum no encontrado"
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
