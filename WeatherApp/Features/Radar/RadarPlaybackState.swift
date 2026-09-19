import Foundation
import Observation

struct RadarFrame: Identifiable, Hashable, Sendable {
    let id: String
    let timestamp: Date
    let tileTemplate: URL
}

@MainActor
@Observable
final class RadarPlaybackState {
    var frames: [RadarFrame] = []
    var selectedIndex = 0
    var isPlaying = false
    var layer: RadarLayer = .reflectivity

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

    func replaceFrames(_ newFrames: [RadarFrame]) {
        frames = newFrames.sorted { $0.timestamp < $1.timestamp }
        selectedIndex = max(0, frames.count - 1)
        if frames.count < 2 {
            isPlaying = false
        }
    }
}

enum RadarLayer: String, CaseIterable, Identifiable {
    case reflectivity
    case alerts

    var id: Self { self }

    var title: String {
        switch self {
        case .reflectivity: "Reflectivity"
        case .alerts: "Alerts"
        }
    }

    var symbol: String {
        switch self {
        case .reflectivity: "cloud.rain"
        case .alerts: "exclamationmark.triangle"
        }
    }
}
