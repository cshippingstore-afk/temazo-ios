import Foundation

struct PlayerState: Equatable {
    var currentTrack: Track? = nil
    var isPlaying: Bool = false
    var queue: [Track] = []
    var index: Int = -1
    var ready: Bool = false
    var positionSec: Float = 0
    var durationSec: Float = 0
    var loadingState: LoadingState = .idle
    var lastError: String? = nil
}

enum LoadingState: String, Equatable {
    case idle
    case extracting    // YouTubeKit fetcheando URL
    case ready         // AVPlayer listo
    case playing       // AVPlayer reproduciendo
    case stalled       // AVPlayer esperando datos
    case failed        // error
}
