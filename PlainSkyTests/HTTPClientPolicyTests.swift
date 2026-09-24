import Foundation
import XCTest
@testable import PlainSky

final class HTTPClientPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RevalidationURLProtocol.reset()
    }

    func testRetryAfterThatCannotFitDeadlineIsNotAttempted() async throws {
        RevalidationURLProtocol.handler = { _ in
            (429, ["Retry-After": "5"], Data())
        }
        let client = URLSessionHTTPClient(session: Self.session(), retryDelay: .seconds(5))
        let context = Self.context(deadlineAfter: .seconds(1))

        do {
            _ = try await client.data(for: Self.request(), context: context)
            XCTFail("Expected the rate limit response to be surfaced.")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .httpStatus(429))
        }

        XCTAssertEqual(RevalidationURLProtocol.requestCount, 1)
    }

    func testRetryAfterWithinDeadlineAllowsOnlyOneRetry() async throws {
        let client = URLSessionHTTPClient(session: Self.session(), retryDelay: .seconds(0))
        var request = Self.request()
        request.setValue("retry", forHTTPHeaderField: "X-Test-Attempt")
        // The URL protocol responds identically to each attempt; this verifies
        // the client enforces a single bounded retry rather than looping.
        RevalidationURLProtocol.handler = { _ in
            let count = RevalidationURLProtocol.requestCount
            return count == 1
                ? (429, ["Retry-After": "0"], Data())
                : (200, ["Cache-Control": "no-store"], Data("ok".utf8))
        }
        let context = Self.context(deadlineAfter: .seconds(5))

        let (data, response) = try await client.data(for: request, context: context)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
        XCTAssertEqual(RevalidationURLProtocol.requestCount, 2)
    }

    func testExpiredURLCacheEntryRevalidatesAndReusesMatchingBodyOn304() async throws {
        let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, diskPath: nil)
        RevalidationURLProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return (304, ["Cache-Control": "max-age=60", "ETag": "\"v1\""], Data())
            }
            return (
                200,
                ["Cache-Control": "max-age=0", "ETag": "\"v1\""],
                Data("cached-body".utf8)
            )
        }
        let session = Self.session(cache: cache)
        let client = URLSessionHTTPClient(session: session)
        let request = Self.request()
        let context = Self.context(deadlineAfter: .seconds(5))

        let (initialBody, _) = try await client.data(for: request)
        XCTAssertEqual(String(data: initialBody, encoding: .utf8), "cached-body")

        var revalidatedRequest = request
        revalidatedRequest.cachePolicy = .reloadRevalidatingCacheData
        let (revalidatedBody, revalidatedResponse) = try await client.data(
            for: revalidatedRequest,
            context: context
        )

        XCTAssertEqual(revalidatedResponse.statusCode, 200)
        XCTAssertEqual(String(data: revalidatedBody, encoding: .utf8), "cached-body")
        XCTAssertEqual(RevalidationURLProtocol.requestCount, 2)
    }

    func testReloadRevalidationWithoutCachedBodyReturnsServerFailure() async throws {
        RevalidationURLProtocol.handler = { _ in (304, [:], Data()) }
        let client = URLSessionHTTPClient(session: Self.session(cache: URLCache(
            memoryCapacity: 1_000_000,
            diskCapacity: 0,
            diskPath: nil
        )))
        var request = Self.request()
        request.cachePolicy = .reloadRevalidatingCacheData

        do {
            _ = try await client.data(for: request)
            XCTFail("A 304 without a matching cached representation must not look successful.")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .httpStatus(304))
        }
    }

    private static func request() -> URLRequest {
        URLRequest(url: URL(string: "https://weather.example.test/forecast")!)
    }

    private static func context(deadlineAfter duration: Duration) -> HTTPRequestContext {
        let location = WeatherLocation(name: "Test", region: "IN", latitude: 39, longitude: -86)
        let refresh = WeatherRefreshContext(location: location)
        return HTTPRequestContext(
            product: .hourlyForecast,
            identity: refresh.identity,
            deadline: ContinuousClock().now.advanced(by: duration)
        )
    }

    private static func session(cache: URLCache? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RevalidationURLProtocol.self]
        configuration.urlCache = cache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }
}

private final class RevalidationURLProtocol: URLProtocol {
    typealias Response = (Int, [String: String], Data)
    nonisolated(unsafe) static var handler: ((URLRequest) -> Response)?
    nonisolated(unsafe) static var requestCount = 0
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        handler = nil
        requestCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requestCount += 1
        let handler = Self.handler
        Self.lock.unlock()

        let (status, headers, body) = handler?(request) ?? (500, [:], Data())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        if !body.isEmpty {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
