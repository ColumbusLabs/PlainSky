import Foundation
import Observation

struct RadarFrame: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case observed
        case forecast
    }

    let id: String
    let timestamp: Date
    let serviceURL: URL
    let layerName: String
    var kind: Kind = .observed
}

@MainActor
@Observable
final class RadarPlaybackState {
    var frames: [RadarFrame] = []
    var selectedIndex = 0
    var isPlaying = false
    /// Frames whose on-screen tiles are already downloaded and can be shown without a gap.
    var readyFrameIDs: Set<String> = []

    var nextIndex: Int {
        frames.isEmpty ? 0 : (selectedIndex + 1) % frames.count
    }

    var isNextFrameReady: Bool {
        guard frames.indices.contains(nextIndex) else { return true }
        return readyFrameIDs.contains(frames[nextIndex].id)
    }

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

    var latestObservedIndex: Int? {
        frames.lastIndex { $0.kind == .observed }
    }

    var firstForecastIndex: Int? {
        frames.firstIndex { $0.kind == .forecast }
    }

    func replaceFrames(_ newFrames: [RadarFrame]) {
        frames = newFrames.sorted { $0.timestamp < $1.timestamp }
        selectedIndex = latestObservedIndex ?? max(0, frames.count - 1)

        if frames.count < 2 {
            isPlaying = false
        }
    }
}
