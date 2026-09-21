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

    func testPrimarySnapshotIsDeliveredBeforeSupplementalFinishes() async throws {
        let repository = LiveWeatherRepository(
            primary: primaryProvider(),
            supplemental: SlowSupplementalProvider(
                payload: SupplementalWeatherPayload(
                    currentFallback: nil,
                    minutePrecipitation: MockWeather.snapshot.minutePrecipitation,
                    solar: MockWeather.snapshot.solar
                ),
                delay: .milliseconds(150)
            ),
            supplementalTimeout: .seconds(2)
        )

        var deliveredSnapshots: [WeatherSnapshot] = []
        let finalSnapshot = try await repository.load(
            location: MockWeather.snapshot.location
        ) { snapshot in
            deliveredSnapshots.append(snapshot)
        }

        let primarySnapshot = try XCTUnwrap(deliveredSnapshots.first)
        XCTAssertEqual(deliveredSnapshots.count, 1)
        XCTAssertEqual(primarySnapshot.availability(for: .minutePrecipitation), .loading)
        XCTAssertEqual(primarySnapshot.availability(for: .uvIndex), .loading)
        XCTAssertEqual(primarySnapshot.availability(for: .solarEvents), .loading)
        XCTAssertEqual(primarySnapshot.availability(for: .alerts), .available)
        XCTAssertTrue(primarySnapshot.minutePrecipitation.isEmpty)

        XCTAssertEqual(finalSnapshot.availability(for: .minutePrecipitation), .available)
        XCTAssertFalse(finalSnapshot.minutePrecipitation.isEmpty)
        XCTAssertNotNil(finalSnapshot.solar)
    }

    func testSupplementalTimeoutMarksProductsUnavailable() async throws {
        let repository = LiveWeatherRepository(
            primary: primaryProvider(),
            supplemental: SlowSupplementalProvider(
                payload: SupplementalWeatherPayload(
                    currentFallback: nil,
                    minutePrecipitation: MockWeather.snapshot.minutePrecipitation,
                    solar: MockWeather.snapshot.solar
                ),
                delay: .seconds(5)
            ),
            supplementalTimeout: .milliseconds(50)
        )

        let snapshot = try await repository.load(location: MockWeather.snapshot.location)

        XCTAssertEqual(
            snapshot.availability(for: .minutePrecipitation),
            .unavailable("Supplemental weather did not respond in time. It will retry on the next refresh.")
        )
        XCTAssertFalse(snapshot.hourly.isEmpty)
    }

    func testSupplementalTimeoutDoesNotWaitForUncooperativeProvider() async throws {
        let repository = LiveWeatherRepository(
            primary: primaryProvider(),
            supplemental: UncooperativeSupplementalProvider(delay: 3),
            supplementalTimeout: .milliseconds(50)
        )

        let start = ContinuousClock.now
        let snapshot = try await repository.load(location: MockWeather.snapshot.location)
        let elapsed = start.duration(to: .now)

        XCTAssertEqual(
            snapshot.availability(for: .uvIndex),
            .unavailable("Supplemental weather did not respond in time. It will retry on the next refresh.")
        )
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testCancellationWhileWaitingForSupplementalReturnsPromptly() async throws {
        let probe = SupplementalStartProbe()
        let repository = LiveWeatherRepository(
            primary: primaryProvider(),
            supplemental: UncooperativeSupplementalProvider(
                delay: 3,
                probe: probe
            ),
            supplementalTimeout: .seconds(30)
        )

        let load = Task {
            try await repository.load(location: MockWeather.snapshot.location)
        }

        for _ in 0..<1_000 {
            if await probe.hasStarted {
                break
            }
            await Task.yield()
        }
        let providerStarted = await probe.hasStarted
        XCTAssertTrue(providerStarted)

        let start = ContinuousClock.now
        load.cancel()

        do {
            _ = try await load.value
            XCTFail("Expected cancellation to terminate the repository load.")
        } catch is CancellationError {
            XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnmappedSupplementalErrorDoesNotLeakDaemonText() async throws {
        let repository = LiveWeatherRepository(
            primary: primaryProvider(),
            supplemental: RawErrorSupplementalProvider()
        )

        let snapshot = try await repository.load(location: MockWeather.snapshot.location)

        XCTAssertEqual(
            snapshot.availability(for: .uvIndex),
            .unavailable("Supplemental weather is temporarily unavailable.")
        )
        XCTAssertEqual(
            snapshot.current.temperature,
            MockWeather.snapshot.current.temperature
        )
    }

    private func primaryProvider() -> FakePrimaryProvider {
        FakePrimaryProvider(
            payload: PrimaryWeatherPayload(
                current: MockWeather.snapshot.current,
                hourly: MockWeather.snapshot.hourly,
                daily: MockWeather.snapshot.daily,
                alerts: []
            )
        )
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

private struct SlowSupplementalProvider: SupplementalWeatherProviding {
    let payload: SupplementalWeatherPayload
    let delay: Duration

    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        try await Task.sleep(for: delay)
        return payload
    }
}

private struct RawErrorSupplementalProvider: SupplementalWeatherProviding {
    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        throw NSError(
            domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors",
            code: 2
        )
    }
}

private struct UncooperativeSupplementalProvider: SupplementalWeatherProviding {
    let delay: TimeInterval
    let probe: SupplementalStartProbe?

    init(delay: TimeInterval, probe: SupplementalStartProbe? = nil) {
        self.delay = delay
        self.probe = probe
    }

    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        await probe?.markStarted()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                continuation.resume(
                    returning: SupplementalWeatherPayload(
                        currentFallback: nil,
                        minutePrecipitation: [],
                        solar: nil
                    )
                )
            }
        }
    }
}

private actor SupplementalStartProbe {
    private(set) var hasStarted = false

    func markStarted() {
        hasStarted = true
    }
}
