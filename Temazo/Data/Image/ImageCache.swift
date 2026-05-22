import Foundation
import UIKit
import SwiftUI

/// Cache compartida en memoria + disco para covers/avatars.
/// AsyncImage de SwiftUI usa URLSession.shared cuya `urlCache` lo gestiona,
/// así que aquí solo tunamos los límites para tener más capacidad
/// (Apple por defecto es ridículamente pequeña).
enum ImageCacheSetup {
    private static var configured = false

    static func configureOnce() {
        guard !configured else { return }
        configured = true
        // 50 MB RAM + 200 MB disco compartidos entre todas las request.
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024,
                             diskCapacity: 200 * 1024 * 1024,
                             diskPath: "TemazoImageCache")
        URLCache.shared = cache
    }
}

/// Vista wrapper que pinta caché-aware. Mantiene la AsyncImage API pero con
/// URLRequest custom que pide cacheo agresivo (returnCacheDataElseLoad).
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage? = nil

    init(url: URL?,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let img = image {
                content(Image(uiImage: img))
            } else {
                placeholder()
                    .task(id: url) { await load() }
            }
        }
    }

    private func load() async {
        guard let url = url else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad
        if let data = try? await URLSession.shared.data(for: req).0,
           let img = UIImage(data: data) {
            image = img
        }
    }
}
