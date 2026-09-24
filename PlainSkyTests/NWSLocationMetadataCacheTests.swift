import Foundation
import XCTest
@testable import PlainSky

final class NWSLocationMetadataCacheTests: XCTestCase {
    func testExactCoordinateKeyDoesNotReuseNearbyRoutingMetadata() async throws {
        let cache = NWSLocationMetadataCache(fileURL: nil)
        let first = Self.location(latitude: 39.0000)
        let nearby = Self.location(latitude: 39.0001)
        let loads = AsyncCounter()

        let firstPoint = try await cache.point(for: first) {
            await loads.increment()
            return NWSMetadataCacheResult(value: Self.point(grid: "IND"))
        }
        let nearbyPoint = try await cache.point(for: nearby) {
            await loads.increment()
            return NWSMetadataCacheResult(value: Self.point(grid: "LOT"))
        }

        XCTAssertEqual(firstPoint.gridId, "IND")
        XCTAssertEqual(nearbyPoint.gridId, "LOT")
        let loadCount = await loads.value
        XCTAssertEqual(loadCount, 2)
    }

    func testConcurrentExactPointLookupsShareOneRequest() async throws {
        let cache = NWSLocationMetadataCache(fileURL: nil)
        let location = Self.location()
        let gate = AsyncRequestGate()
        let loads = AsyncCounter()
        let first = Task {
            try await cache.point(for: location) {
                await gate.block()
                return NWSMetadataCacheResult(value: Self.point(grid: "IND"))
            }
        }
        await gate.waitUntilStarted()

        let second = Task {
            try await cache.point(for: location) {
                await loads.increment()
                return NWSMetadataCacheResult(value: Self.point(grid: "LOT"))
            }
        }
        await gate.release()

        let firstPoint = try await first.value
        let secondPoint = try await second.value
        XCTAssertEqual(firstPoint.gridId, "IND")
        XCTAssertEqual(secondPoint.gridId, "IND")
        let loadCount = await loads.value
        XCTAssertEqual(loadCount, 0)
    }

    func testExpiredDiskMetadataIsReplacedAfterLoaderCompletes() async throws {
        let fileURL = Self.cacheFileURL()
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        let location = Self.location()
        let original = NWSLocationMetadataCache(
            fileURL: fileURL,
            timeToLive: 60,
            now: { originalDate }
        )
        _ = try await original.point(for: location) {
            NWSMetadataCacheResult(value: Self.point(grid: "IND"))
        }

        let justBeforeExpiry = NWSLocationMetadataCache(
            fileURL: fileURL,
            timeToLive: 60,
            now: { originalDate.addingTimeInterval(59) }
        )
        let stillValid = try await justBeforeExpiry.point(for: location) {
            NWSMetadataCacheResult(value: Self.point(grid: "LOT"))
        }
        XCTAssertEqual(stillValid.gridId, "IND")

        let exactlyAtExpiry = NWSLocationMetadataCache(
            fileURL: fileURL,
            timeToLive: 60,
            now: { originalDate.addingTimeInterval(60) }
        )
        let updated = try await exactlyAtExpiry.point(for: location) {
            NWSMetadataCacheResult(value: Self.point(grid: "LOT"))
        }

        XCTAssertEqual(updated.gridId, "LOT")
    }

    func testCorruptMetadataFileBecomesCacheMiss() async throws {
        let fileURL = Self.cacheFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        let cache = NWSLocationMetadataCache(fileURL: fileURL)
        let loads = AsyncCounter()

        let point = try await cache.point(for: Self.location()) {
            await loads.increment()
            return NWSMetadataCacheResult(value: Self.point(grid: "IND"))
        }

        XCTAssertEqual(point.gridId, "IND")
        let loadCount = await loads.value
        XCTAssertEqual(loadCount, 1)
    }

    func testStationDirectoryIsReusedOnlyForMatchingRouteRevision() async throws {
        let cache = NWSLocationMetadataCache(fileURL: nil)
        let location = Self.location()
        _ = try await cache.point(for: location) {
            NWSMetadataCacheResult(value: Self.point(grid: "IND"))
        }
        let loads = AsyncCounter()
        let station = NWSStationProperties(stationIdentifier: "KIND", name: "Indianapolis")

        let first = try await cache.stationDirectory(for: location, routeRevision: "IND:1:2") {
            await loads.increment()
            return NWSMetadataCacheResult(value: [station])
        }
        let second = try await cache.stationDirectory(for: location, routeRevision: "IND:1:2") {
            await loads.increment()
            return NWSMetadataCacheResult(value: [])
        }
        await cache.invalidate(location)
        _ = try await cache.point(for: location) {
            NWSMetadataCacheResult(value: Self.point(grid: "LOT"))
        }
        let changedRoute = try await cache.stationDirectory(for: location, routeRevision: "LOT:1:2") {
            await loads.increment()
            return NWSMetadataCacheResult(value: [station])
        }

        XCTAssertEqual(first.map(\.stationIdentifier), ["KIND"])
        XCTAssertEqual(second.map(\.stationIdentifier), ["KIND"])
        XCTAssertEqual(changedRoute.map(\.stationIdentifier), ["KIND"])
        let loadCount = await loads.value
        XCTAssertEqual(loadCount, 2)
    }

    func testPointCacheHonorsShorterCacheControlLifetimeAndAge() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = MutableDateClock(start)
        let cache = NWSLocationMetadataCache(
            fileURL: nil,
            timeToLive: 24 * 60 * 60,
            now: { clock.now() }
        )
        let loads = AsyncCounter()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.weather.gov/points/39,-86")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "public, max-age=60", "Age": "20"]
        )!
        let policy = NWSMetadataCachePolicy(response: response)

        _ = try await cache.point(for: Self.location()) {
            NWSMetadataCacheResult(value: Self.point(grid: "IND"), policy: policy)
        }
        clock.advance(by: 39)
        let cached = try await cache.point(for: Self.location()) {
            await loads.increment()
            return NWSMetadataCacheResult(value: Self.point(grid: "LOT"))
        }
        XCTAssertEqual(cached.gridId, "IND")

        clock.advance(by: 1)
        let refreshed = try await cache.point(for: Self.location()) {
            await loads.increment()
            return NWSMetadataCacheResult(value: Self.point(grid: "LOT"))
        }
        XCTAssertEqual(refreshed.gridId, "LOT")
        let loadCount = await loads.value
        XCTAssertEqual(loadCount, 1)
    }

    func testNoStorePointResponseIsNotRetained() async throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.weather.gov/points/39,-86")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "no-store"]
        )!
        let policy = NWSMetadataCachePolicy(response: response)
        let cache = NWSLocationMetadataCache(fileURL: nil)
        let loads = AsyncCounter()

        _ = try await cache.point(for: Self.location()) {
            await loads.increment()
            return NWSMetadataCacheResult(value: Self.point(grid: "IND"), policy: policy)
        }
        let second = try await cache.point(for: Self.location()) {
            await loads.increment()
            return NWSMetadataCacheResult(value: Self.point(grid: "LOT"))
        }

        XCTAssertEqual(second.gridId, "LOT")
        let loadCount = await loads.value
        XCTAssertEqual(loadCount, 2)
    }

    private static func location(latitude: Double = 39) -> WeatherLocation {
        WeatherLocation(name: "Test", region: "IN", latitude: latitude, longitude: -86)
    }

    private static func point(grid: String) -> NWSPointProperties {
        NWSPointProperties(
            gridId: grid,
            gridX: 1,
            gridY: 2,
            forecast: URL(string: "https://api.weather.gov/gridpoints/\(grid)/1,2/forecast")!,
            forecastHourly: URL(string: "https://api.weather.gov/gridpoints/\(grid)/1,2/forecast/hourly")!,
            forecastGridData: URL(string: "https://api.weather.gov/gridpoints/\(grid)/1,2")!,
            observationStations: URL(string: "https://api.weather.gov/gridpoints/\(grid)/1,2/stations")!,
            timeZone: "America/Indiana/Indianapolis"
        )
    }

    private static func cacheFileURL() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlainSkyMetadataCacheTests", isDirectory: true)
        return root.appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
    }
}

private actor AsyncRequestGate {
    private var hasStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var requestContinuation: CheckedContinuation<Void, Never>?

    func block() async {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func release() {
        requestContinuation?.resume()
        requestContinuation = nil
    }
}

private actor AsyncCounter {
    private(set) var value = 0

    func increment() { value += 1 }
}

private final class MutableDateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date.addTimeInterval(interval)
    }
}
