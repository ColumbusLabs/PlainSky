import XCTest
@testable import PlainSky

final class WeatherFreshnessPolicyTests: XCTestCase {
    func testNWSObservationAgeAndFutureSkewBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let policy = WeatherFreshnessPolicy(now: { now })

        XCTAssertTrue(policy.isFresh(
            metadata(
                provider: .nwsObservation,
                validatedAt: now,
                sourceObservedAt: now.addingTimeInterval(-90 * 60)
            ),
            for: .currentConditions
        ))
        XCTAssertFalse(policy.isFresh(
            metadata(
                provider: .nwsObservation,
                validatedAt: now,
                sourceObservedAt: now.addingTimeInterval(-90 * 60 - 1)
            ),
            for: .currentConditions
        ))
        XCTAssertTrue(policy.isFresh(
            metadata(
                provider: .nwsObservation,
                validatedAt: now,
                sourceObservedAt: now.addingTimeInterval(10 * 60)
            ),
            for: .currentConditions
        ))
        XCTAssertFalse(policy.isFresh(
            metadata(
                provider: .nwsObservation,
                validatedAt: now,
                sourceObservedAt: now.addingTimeInterval(10 * 60 + 1)
            ),
            for: .currentConditions
        ))
    }

    func testProductValidationCapsAndProviderExpiryAreIndependent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let policy = WeatherFreshnessPolicy(now: { now })

        XCTAssertTrue(policy.isFresh(
            metadata(
                provider: .nwsForecast,
                validatedAt: now.addingTimeInterval(-14 * 60),
                sourceIssuedAt: now.addingTimeInterval(-11 * 60 * 60)
            ),
            for: .hourlyForecast
        ))
        XCTAssertFalse(policy.isFresh(
            metadata(
                provider: .nwsForecast,
                validatedAt: now.addingTimeInterval(-15 * 60 - 1),
                sourceIssuedAt: now.addingTimeInterval(-11 * 60 * 60)
            ),
            for: .hourlyForecast
        ))
        XCTAssertFalse(policy.isFresh(
            metadata(
                provider: .weatherKit,
                validatedAt: now,
                sourceObservedAt: now,
                expiresAt: now
            ),
            for: .currentConditions
        ))
    }

    func testAlertAgeAndEmptySuccessUseTheirOwnValidationTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let policy = WeatherFreshnessPolicy(now: { now })

        XCTAssertTrue(policy.isFresh(
            metadata(
                provider: .nwsForecast,
                validatedAt: now.addingTimeInterval(-60)
            ),
            for: .alerts
        ))
        XCTAssertFalse(policy.isFresh(
            metadata(
                provider: .nwsForecast,
                validatedAt: now.addingTimeInterval(-61)
            ),
            for: .alerts
        ))
    }

    func testSolarFreshnessUsesTheSelectedLocationLocalDate() throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-20T03:30:00Z"))
        let nextLocalDate = try XCTUnwrap(NWSParsing.date("2026-09-20T04:00:00Z"))
        let policy = WeatherFreshnessPolicy(now: { now })
        let solar = metadata(
            provider: .weatherKit,
            validatedAt: now,
            validFrom: nextLocalDate
        )

        XCTAssertFalse(policy.isFresh(
            solar,
            for: .solarEvents,
            timeZoneIdentifier: "America/Indiana/Indianapolis"
        ))
        XCTAssertTrue(policy.isFresh(
            solar,
            for: .solarEvents,
            timeZoneIdentifier: "UTC"
        ))
    }

    func testFutureValidationBeyondClockSkewAndLongResumeBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let policy = WeatherFreshnessPolicy(now: { now })
        let futureValidation = metadata(
            provider: .nwsForecast,
            validatedAt: now.addingTimeInterval(10 * 60 + 1),
            sourceIssuedAt: now
        )

        XCTAssertFalse(policy.isFresh(futureValidation, for: .dailyForecast))
        XCTAssertFalse(policy.isLongResume(since: now.addingTimeInterval(-299)))
        XCTAssertTrue(policy.isLongResume(since: now.addingTimeInterval(-300)))
    }

    private func metadata(
        provider: WeatherProvider,
        validatedAt: Date,
        sourceObservedAt: Date? = nil,
        sourceIssuedAt: Date? = nil,
        validFrom: Date? = nil,
        expiresAt: Date? = nil
    ) -> WeatherValidationMetadata {
        WeatherValidationMetadata(
            provider: provider,
            validatedAt: validatedAt,
            sourceObservedAt: sourceObservedAt,
            sourceIssuedAt: sourceIssuedAt,
            validFrom: validFrom,
            expiresAt: expiresAt
        )
    }
}
