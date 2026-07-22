import Foundation
import Combine

/// Bus global para mostrar TrackOptionsSheet sin propagar callbacks por toda la jerarquía.
/// MainScreen observa este bus y muestra el sheet con sus callbacks (artista/álbum/playlist/share).
@MainActor
final class TrackOptionsBus: ObservableObject {
    static let shared = TrackOptionsBus()
    @Published var selectedTrack: Track? = nil

    private init() {}

    func show(_ t: Track) { selectedTrack = t }
    func dismiss() { selectedTrack = nil }
}
