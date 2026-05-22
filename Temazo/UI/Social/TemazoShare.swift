import SwiftUI
import UIKit

/// Helpers para compartir tracks / playlists / artistas / usuarios via
/// UIActivityViewController. Devuelve los items y abre el sheet del sistema.
enum TemazoShare {
    static func shareTrack(_ t: Track) {
        let artistSlug = t.artistSlug ?? ""
        let trackSlug = t.slug ?? ""
        let url = "https://temazo.es/\(artistSlug)/\(trackSlug)"
        let text = "\(t.title) — \(t.artistName ?? "")\n\(url)"
        present(items: [text])
    }

    static func shareArtist(id: Int64? = nil, slug: String?, name: String?) {
        let s = slug ?? ""
        let url = "https://temazo.es/\(s)"
        let text = "\(name ?? "Artista en Temazo")\n\(url)"
        present(items: [text])
    }

    static func sharePlaylist(id: Int64, name: String, ownerUsername: String?) {
        let url = "https://temazo.es/playlist/\(id)"
        let owner = ownerUsername.map { " · @\($0)" } ?? ""
        let text = "\(name)\(owner)\n\(url)"
        present(items: [text])
    }

    static func shareUser(_ username: String) {
        let url = "https://temazo.es/@\(username)"
        present(items: ["Sígueme en Temazo: @\(username)\n\(url)"])
    }

    private static func present(items: [Any]) {
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            // Encuentra el top-most controller para evitar warnings
            var top: UIViewController = root
            while let presented = top.presentedViewController { top = presented }
            top.present(av, animated: true)
        }
    }
}
