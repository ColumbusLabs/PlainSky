import XCTest
@testable import PlainSky

final class WeatherKitErrorMapperTests: XCTestCase {
    func testDaemonAuthenticationFailureMapsToCapabilityGuidance() {
        let error = NSError(
            domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors",
            code: 2
        )

        XCTAssertEqual(
            WeatherKitErrorMapper.message(for: error),
            WeatherKitErrorMapper.authenticationMessage
        )
    }

    func testUnknownErrorMapsToTemporaryMessage() {
        let error = NSError(domain: "NSURLErrorDomain", code: -1009)

        XCTAssertEqual(
            WeatherKitErrorMapper.message(for: error),
            WeatherKitErrorMapper.temporaryMessage
        )
    }
}
