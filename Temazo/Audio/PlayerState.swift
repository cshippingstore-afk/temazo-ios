import Foundation

struct PlayerState: Equatable {
    var currentTrack: Track? = nil
    var isPlaying: Bool = false
    var queue: [Track] = []
    var index: Int = -1
    var ready: Bool = false   // YT player JS API ready
    var positionSec: Float = 0
    var durationSec: Float = 0
}
