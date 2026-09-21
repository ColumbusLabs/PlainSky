import Foundation
import Observation

struct RadarFrame: Identifiable, Hashable, Sendable {
    let id: String
    let timestamp: Date
    let serviceURL: URL
    let layerName: String
}

@MainActor
@Observable
final class RadarPlaybackState {
    var frames: [RadarFrame] = []
    var selectedIndex = 0
    var isPlaying = false

    var selectedFrame: RadarFrame? {
        guard frames.indices.contains(selectedIndex) else { return nil }
        return frames[selectedIndex]
    }

    func select(index: Int) {
        guard frames.indices.contains(index) else { return }
        selectedIndex = index
    }

    func togglePlayback() {
        guard frames.count > 1 else {
            isPlaying = false
            return
        }

        isPlaying.toggle()
    }

    func advance() {
        guard frames.count > 1 else {
            isPlaying = false
            return
        }

        selectedIndex = (selectedIndex + 1) % frames.count
    }

    func replaceFrames(_ newFrames: [RadarFrame]) {
        frames = newFrames.sorted { $0.timestamp < $1.timestamp }
        selectedIndex = max(0, frames.count - 1)

        if frames.count < 2 {
            isPlaying = false
        }
    }
}
