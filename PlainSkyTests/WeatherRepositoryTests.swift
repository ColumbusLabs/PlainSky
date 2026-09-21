import XCTest
@testable import PlainSky

@MainActor
final class WeatherRepositoryTests: XCTestCase {
    func testPrimaryCurrentConditionsWinAsWholeGroup() async throws {
        var primaryCurrent = MockWeather.snapshot.current
        primaryCurrent.temperature = 51
        primaryCurrent.humidity = 0.41
        primaryCurrent.source.provider = .nwsObservation

        var fallback = MockWeather.snapshot.current
        fallback.temperature = 89
        fallback.humidity = 0.92
        fallback.source.provider = .weatherKit

        let repository = LiveWeatherRepository(
            primary: FakePrimaryProvider(
                payload: PrimaryWeatherPayload(
                    current: primaryCurrent,
                    hourly: MockWeather.snapshot.hourly,
                    daily: MockWeather.snapshot.daily,
                    alerts: []
                )
            ),
            supplemental: FakeSupplementalProvider(
                payload: SupplementalWeatherPayload(
                    currentFallback: fallback,
                    minutePrecipitation: MockWeather.snapshot.minutePrecipitation,
                    solar: MockWeather.snapshot.solar
                )
            )
        )

        let snapshot = try await repository.load(location: MockWeather.snapshot.location)

        XCTAssertEqual(snapshot.current.temperature, 51)
        XCTAssertEqual(snapshot.current.humidity, 0.41)
        XCTAssertEqual(snapshot.current.source.provider, .nwsObservation)
        XCTAssertFalse(snapshot.minutePrecipitation.isEmpty)
        XCTAssertEqual(snapshot.availability(for: .minutePrecipitation), .available)
    }

    func testSupplementalCurrentUsedOnlyWhenPrimaryCurrentMissing() async throws {
        var fallback = MockWeather.snapshot.current
        fallback.temperature = 77
        fallback.source.provider = .weatherKit

        let repository = LiveWeatherRepository(
            primary: FakePrimaryProvider(
                payload: PrimaryWeatherPayload(
                    current: nil,
                    hourly: MockWeather.snapshot.hourly,
                    daily: MockWeather.snapshot.daily,
                    alerts: []
                )
            ),
            supplemental: FakeSupplementalProvider(
                payload: SupplementalWeatherPayload(
                    currentFallback: fallback,
                    minutePrecipitation: [],
                    solar: nil
                )
            )
        )

        let snapshot = try await repository.load(location: MockWeather.snapshot.location)

        XCTAssertEqual(snapshot.current.temperature, 77)
        XCTAssertEqual(snapshot.current.source.provider, .weatherKit)
        XCTAssertEqual(
            snapshot.availability(for: .minutePrecipitation),
            .unsupported("Next-hour precipitation is not available for this location.")
        )
    }

    func testSupplementalFailureIsRecordedWithoutDestroyingPrimaryForecast() async throws {
        let repository = LiveWeatherRepository(
            primary: FakePrimaryProvider(
                payload: PrimaryWeatherPayload(
                    current: MockWeather.snapshot.current,
                    hourly: MockWeather.snapshot.hourly,
                    daily: MockWeather.snapshot.daily,
                    alerts: []
                )
            ),
            supplemental: ThrowingSupplementalProvider()
        )

        let snapshot = try await repository.load(location: MockWeather.snapshot.location)

        XCTAssertFalse(snapshot.hourly.isEmpty)

        guard case .unavailable = snapshot.availability(for: .minutePrecipitation) else {
            return XCTFail("Expected minute precipitation to retain supplemental failure state.")
        }

        guard case .unavailable = snapshot.availability(for: .uvIndex) else {
            return XCTFail("Expected UV to retain supplemental failure state.")
        }
    }

    func testMissingCurrentFromBothProvidersFails() async {
        let repository = LiveWeatherRepository(
            primary: FakePrimaryProvider(
                payload: PrimaryWeatherPayload(
                    current: nil,
                    hourly: [],
                    daily: [],
                    alerts: []
                )
            ),
            supplemental: FakeSupplementalProvider(
                payload: SupplementalWeatherPayload(
                    currentFallback: nil,
                    minutePrecipitation: [],
                    solar: nil
                )
            )
        )

        do {
            _ = try await repository.load(location: MockWeather.snapshot.location)
            XCTFail("Expected missing required current conditions to fail.")
        } catch let error as ProviderError {
            guard case .missingRequiredData = error else {
                return XCTFail("Unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct FakePrimaryProvider: PrimaryWeatherProviding {
    let payload: PrimaryWeatherPayload

    func weather(for location: WeatherLocation) async throws -> PrimaryWeatherPayload {
        payload
    }
}

private struct FakeSupplementalProvider: SupplementalWeatherProviding {
    let payload: SupplementalWeatherPayload

    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        payload
    }
}

private struct ThrowingSupplementalProvider: SupplementalWeatherProviding {
    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        throw ProviderError.notConfigured("Supplemental provider unavailable in test.")
    }
}
