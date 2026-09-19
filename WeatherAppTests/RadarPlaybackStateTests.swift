import XCTest
@testable import WeatherApp

@MainActor
final class RadarPlaybackStateTests: XCTestCase {
    func testReplaceFramesSortsAndSelectsNewest() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/ows"))
        let base = Date(timeIntervalSince1970: 1_000)

        let state = RadarPlaybackState()
        state.replaceFrames([
            RadarFrame(id: "later", timestamp: base.addingTimeInterval(120), serviceURL: url, layerName: "radar"),
            RadarFrame(id: "earlier", timestamp: base, serviceURL: url, layerName: "radar")
        ])

        XCTAssertEqual(state.frames.map(\.id), ["earlier", "later"])
        XCTAssertEqual(state.selectedFrame?.id, "later")
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testAdvanceWrapsAcrossAvailableFrames() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/ows"))
        let base = Date(timeIntervalSince1970: 1_000)

        let state = RadarPlaybackState()
        state.replaceFrames([
            RadarFrame(id: "one", timestamp: base, serviceURL: url, layerName: "radar"),
            RadarFrame(id: "two", timestamp: base.addingTimeInterval(60), serviceURL: url, layerName: "radar")
        ])

        state.advance()
        XCTAssertEqual(state.selectedFrame?.id, "one")

        state.advance()
        XCTAssertEqual(state.selectedFrame?.id, "two")
    }

    func testPlaybackCannotStartWithFewerThanTwoFrames() {
        let state = RadarPlaybackState()
        state.togglePlayback()
        XCTAssertFalse(state.isPlaying)
    }
}
