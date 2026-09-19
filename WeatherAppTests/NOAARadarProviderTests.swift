import MapKit
import XCTest
@testable import WeatherApp

final class NOAARadarProviderTests: XCTestCase {
    func testCapabilitiesParserReadsExactAndIntervalTimes() throws {
        let xml = """
        <WMS_Capabilities>
          <Capability>
            <Layer>
              <Layer>
                <Name>conus_bref_qcd</Name>
                <Dimension name="time" units="ISO8601">
                  2026-09-19T22:00:00Z,2026-09-19T22:02:00Z,
                  2026-09-19T22:04:00Z/2026-09-19T22:08:00Z/PT2M
                </Dimension>
              </Layer>
            </Layer>
          </Capability>
        </WMS_Capabilities>
        """

        let times = try RadarTimeParser.frameTimes(from: Data(xml.utf8))

        XCTAssertEqual(times.count, 5)
        XCTAssertEqual(
            times.last,
            ISO8601DateFormatter().date(from: "2026-09-19T22:08:00Z")
        )
    }

    func testProviderKeepsOnlyRecentRealFrameTimes() async throws {
        let xml = """
        <WMS_Capabilities>
          <Capability>
            <Layer>
              <Dimension name="time" units="ISO8601">
                2026-09-19T20:00:00Z,
                2026-09-19T21:00:00Z,
                2026-09-19T21:30:00Z,
                2026-09-19T21:58:00Z,
                2026-09-19T22:00:00Z
              </Dimension>
            </Layer>
          </Capability>
        </WMS_Capabilities>
        """

        let http = RadarCapturingHTTPClient(data: Data(xml.utf8))
        let provider = NOAARadarProvider(
            httpClient: http,
            historyWindow: 60 * 60,
            maximumFrames: 40
        )

        let frames = try await provider.frames(
            for: WeatherLocation(
                name: "Indianapolis",
                region: "Indiana",
                latitude: 39.7684,
                longitude: -86.1581
            )
        )

        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames.first?.layerName, "conus_bref_qcd")
        XCTAssertEqual(
            frames.first?.serviceURL.absoluteString,
            "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows"
        )
        XCTAssertEqual(
            http.lastRequest?.url?.host,
            "opengeo.ncep.noaa.gov"
        )

        let components = try XCTUnwrap(
            URLComponents(
                url: try XCTUnwrap(http.lastRequest?.url),
                resolvingAgainstBaseURL: false
            )
        )

        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "request" })?.value,
            "GetCapabilities"
        )
    }

    func testWMSTileURLUsesExactFrameAndWebMercator() throws {
        let timestamp = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-09-19T22:00:00Z")
        )
        let frame = RadarFrame(
            id: "frame",
            timestamp: timestamp,
            serviceURL: try XCTUnwrap(
                URL(
                    string: "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows"
                )
            ),
            layerName: "conus_bref_qcd"
        )
        let overlay = RadarWMSTileOverlay(frame: frame)

        let url = overlay.url(
            forTilePath: MKTileOverlayPath(
                x: 1,
                y: 1,
                z: 2,
                contentScaleFactor: 1
            )
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )

        XCTAssertEqual(query["LAYERS"], "conus_bref_qcd")
        XCTAssertEqual(query["VERSION"], "1.1.1")
        XCTAssertEqual(query["SRS"], "EPSG:3857")
        XCTAssertEqual(query["TRANSPARENT"], "TRUE")
        XCTAssertEqual(query["TIME"], "2026-09-19T22:00:00Z")
        XCTAssertEqual(query["BBOX"]?.split(separator: ",").count, 4)
    }

    func testProviderRejectsLocationOutsideConfiguredNOAAMosaics() async {
        let provider = NOAARadarProvider(
            httpClient: RadarCapturingHTTPClient(data: Data())
        )

        do {
            _ = try await provider.frames(
                for: WeatherLocation(
                    name: "London",
                    region: "United Kingdom",
                    latitude: 51.5072,
                    longitude: -0.1276
                )
            )
            XCTFail("Expected unsupported radar region.")
        } catch let error as RadarProviderError {
            XCTAssertEqual(error, .unsupportedRegion)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class RadarCapturingHTTPClient: HTTPClient {
    let responseData: Data
    private(set) var lastRequest: URLRequest?

    init(data: Data) {
        self.responseData = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/xml"]
        )!

        return (responseData, response)
    }
}
