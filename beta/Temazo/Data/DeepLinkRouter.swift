import Foundation

/// Universal Links handler — espejo de DeepLinkBus.kt (Android).
/// Cuando alguien comparte un enlace temazo.es y el usuario tiene la app instalada,
/// iOS abre la app y nos entrega el NSUserActivity con la URL.
/// Aquí parseamos el path y disparamos la acción correspondiente.
///
/// URLs soportadas (mismas que web/Android):
///  /<artist-slug>/<song-slug>    → reproducir track (auto-play)
///  /<artist-slug>                → abrir artista
///  /album/<slug>                 → abrir álbum
///  /playlist/<id>                → playlist pública
///  /u/<username>                 → perfil público
///  /@<username>                  → perfil público
///  /eventos                      → eventos
///  /noticias                     → noticias
enum DeepLinkRouter {
    static func handle(url: URL) {
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard !segments.isEmpty else { return }

        let first = segments[0].lowercased()

        // /u/<username>
        if first == "u", segments.count >= 2 {
            NotificationCenter.default.post(
                name: .temazoOpenUserByUsername,
                object: nil,
                userInfo: ["username": segments[1]]
            )
            return
        }
        // /@<username>
        if segments[0].hasPrefix("@"), segments[0].count > 1 {
            NotificationCenter.default.post(
                name: .temazoOpenUserByUsername,
                object: nil,
                userInfo: ["username": String(segments[0].dropFirst())]
            )
            return
        }
        // /playlist/<id>
        if first == "playlist", segments.count >= 2, let pid = Int64(segments[1]) {
            NotificationCenter.default.post(
                name: .temazoOpenPublicPlaylistById,
                object: nil,
                userInfo: ["playlistId": pid]
            )
            return
        }
        // /album/<slug>
        if first == "album", segments.count >= 2 {
            NotificationCenter.default.post(
                name: .temazoOpenAlbumBySlug,
                object: nil,
                userInfo: ["slug": segments[1]]
            )
            return
        }
        // /eventos
        if first == "eventos" {
            NotificationCenter.default.post(name: Notification.Name("temazoOpenEvents"), object: nil)
            return
        }
        // /noticias
        if first == "noticias" {
            NotificationCenter.default.post(name: Notification.Name("temazoOpenNews"), object: nil)
            return
        }

        // /<artist-slug>/<song-slug> → reproducir
        if segments.count >= 2 {
            playTrack(artistSlug: segments[0], trackSlug: segments[1])
            return
        }
        // /<artist-slug>
        if segments.count == 1 {
            NotificationCenter.default.post(
                name: .temazoOpenArtistBySlug,
                object: nil,
                userInfo: ["slug": segments[0]]
            )
        }
    }

    private static func playTrack(artistSlug: String, trackSlug: String) {
        Task {
            do {
                let query = "\(artistSlug) \(trackSlug)".replacingOccurrences(of: "-", with: " ")
                let resp = try await TemazoAPI.shared.search(query, limit: 5)
                let pick = resp.tracks.first(where: { $0.slug == trackSlug }) ?? resp.tracks.first
                guard let t = pick else { return }
                await MainActor.run {
                    Player.shared.playTrack(t, queue: [t], index: 0, source: "deeplink")
                }
            } catch {
                // Silenciar — si el track no aparece, el sistema cae al navegador.
            }
        }
    }
}
