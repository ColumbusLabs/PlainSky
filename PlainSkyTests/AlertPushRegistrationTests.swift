import Foundation
import UserNotifications
import XCTest
@testable import PlainSky

@MainActor
final class AlertPushRegistrationTests: XCTestCase {
    func testAllNWSCategoriesOffUnregistersEvenWhenPrecipitationIsOn() async throws {
        let (suite, defaults, settings, token) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.notificationPreferences = .init(
            warnings: false,
            watches: false,
            advisories: false,
            statements: false,
            precipitationStart: true
        )
        settings.serverAlertsRegistered = true
        settings.registrationFingerprint = "previous-registration"

        AlertRegistrationURLProtocol.reset(statusCode: 204)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let registration = makeRegistration(settings: settings, session: session)

        await registration.sync(force: true)

        let request = try XCTUnwrap(AlertRegistrationURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/v1/devices/\(token)")
        XCTAssertFalse(settings.serverAlertsRegistered)
        XCTAssertNil(settings.registrationFingerprint)
        XCTAssertNil(settings.registeredAt)
    }

    func testEnabledNWSCategoryPostsRoundedCoordinates() async throws {
        let (suite, defaults, settings, _) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.notificationPreferences = .init(
            warnings: true,
            watches: false,
            advisories: false,
            statements: false,
            precipitationStart: false
        )
        settings.homePlace = WeatherLocation(
            name: "Bloomington",
            region: "IN",
            latitude: 39.7684,
            longitude: -86.875
        )

        AlertRegistrationURLProtocol.reset(statusCode: 200)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let registration = makeRegistration(settings: settings, session: session)

        await registration.sync(force: true)

        let request = try XCTUnwrap(AlertRegistrationURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/devices")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["token"] as? String, settings.pushToken)
        XCTAssertEqual(payload["placeName"] as? String, "Bloomington")
        XCTAssertEqual(payload["latitude"] as? Double ?? .nan, 39.77, accuracy: 0.000_001)
        XCTAssertEqual(payload["longitude"] as? Double ?? .nan, -86.87, accuracy: 0.000_001)
        XCTAssertTrue(settings.serverAlertsRegistered)
    }

    func testFailedUnregisterKeepsRegistrationMarkedForALaterSync() async throws {
        let (suite, defaults, settings, _) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.notificationPreferences = .init(
            warnings: false,
            watches: false,
            advisories: false,
            statements: false,
            precipitationStart: true
        )
        settings.serverAlertsRegistered = true

        AlertRegistrationURLProtocol.reset(statusCode: 503)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let registration = makeRegistration(settings: settings, session: session)

        await registration.sync(force: true)

        XCTAssertEqual(AlertRegistrationURLProtocol.capturedRequests.first?.httpMethod, "DELETE")
        XCTAssertTrue(settings.serverAlertsRegistered)
    }

    func testCategoryChangesDuringRegistrationImmediatelyUnregisterAfterPost() async throws {
        let (suite, defaults, settings, _) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.notificationPreferences = .init(
            warnings: true,
            watches: false,
            advisories: false,
            statements: false,
            precipitationStart: true
        )

        let postStarted = expectation(description: "Registration POST is suspended")
        AlertRegistrationURLProtocol.reset(
            statusCode: 200,
            suspendFirstPost: true,
            postStarted: postStarted
        )
        defer { AlertRegistrationURLProtocol.releaseSuspendedPosts() }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let registration = makeRegistration(settings: settings, session: session)

        let initialSync = Task { await registration.sync(force: true) }
        await fulfillment(of: [postStarted], timeout: 5)

        settings.notificationPreferences = .init(
            warnings: false,
            watches: false,
            advisories: false,
            statements: false,
            precipitationStart: true
        )
        await registration.sync()

        AlertRegistrationURLProtocol.releaseSuspendedPosts()
        await initialSync.value

        let methods = AlertRegistrationURLProtocol.capturedRequests.compactMap(\.httpMethod)
        XCTAssertEqual(methods, ["POST", "DELETE"])
        XCTAssertFalse(settings.serverAlertsRegistered)
    }

    private func makeSettings() throws -> (String, UserDefaults, SharedWeatherSettings, String) {
        let suite = "AlertPushRegistrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = SharedWeatherSettings(defaults: defaults)
        let token = String(repeating: "a", count: 64)
        settings.pushToken = token
        settings.homePlace = WeatherLocation(
            name: "Test Place",
            region: "IN",
            latitude: 39.7684,
            longitude: -86.1581
        )
        return (suite, defaults, settings, token)
    }

    private func makeRegistration(settings: SharedWeatherSettings, session: URLSession) -> AlertPushRegistration {
        AlertPushRegistration(
            settings: settings,
            session: session,
            authorizationStatusProvider: { UNAuthorizationStatus.authorized },
            isPreview: { false }
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AlertRegistrationURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class AlertRegistrationURLProtocol: URLProtocol {
    typealias Response = (statusCode: Int, headers: [String: String], body: Data)

    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var response: Response = (200, [:], Data())
    nonisolated(unsafe) private static var suspendFirstPost = false
    nonisolated(unsafe) private static var postStartedExpectation: XCTestExpectation?
    nonisolated(unsafe) private static var suspendedPosts: [AlertRegistrationURLProtocol] = []
    private static let lock = NSLock()

    private var suspendedResponse: Response?

    static var capturedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func reset(
        statusCode: Int,
        suspendFirstPost: Bool = false,
        postStarted: XCTestExpectation? = nil
    ) {
        lock.lock()
        requests = []
        response = (statusCode, [:], Data())
        self.suspendFirstPost = suspendFirstPost
        postStartedExpectation = postStarted
        suspendedPosts = []
        lock.unlock()
    }

    static func releaseSuspendedPosts() {
        lock.lock()
        let posts = suspendedPosts
        suspendedPosts = []
        lock.unlock()

        posts.forEach { $0.finishSuspendedRequest() }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let capturedRequest = Self.captureBody(from: request)
        Self.lock.lock()
        Self.requests.append(capturedRequest)
        let response = Self.response
        let shouldSuspend = Self.suspendFirstPost && request.httpMethod == "POST"
        let startedExpectation = shouldSuspend ? Self.postStartedExpectation : nil
        if shouldSuspend {
            Self.suspendFirstPost = false
            suspendedResponse = response
            Self.suspendedPosts.append(self)
        }
        Self.lock.unlock()

        if shouldSuspend {
            startedExpectation?.fulfill()
            return
        }

        finishLoading(with: response)
    }

    override func stopLoading() {}

    private func finishSuspendedRequest() {
        guard let response = suspendedResponse else { return }
        finishLoading(with: response)
    }

    private func finishLoading(with response: Response) {
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        if !response.body.isEmpty {
            client?.urlProtocol(self, didLoad: response.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func captureBody(from request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }

        var capturedRequest = request
        capturedRequest.httpBodyStream = nil
        capturedRequest.httpBody = data
        return capturedRequest
    }
}
