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

    func testCurrentBecomesUnavailableAtCurrentBudgetWhileWeatherKitContinues() async throws {
        let supplementalProbe = SupplementalStartProbe()
        let currentUnavailable = expectation(description: "Current resolves at its own deadline")
        let location = MockWeather.snapshot.location
        let repository = LiveWeatherRepository(
            primary: FakePrimaryProvider(
                payload: PrimaryWeatherPayload(
                    current: nil,
                    hourly: [],
                    daily: [],
                    alerts: []
                )
            ),
            supplemental: UncooperativeSupplementalProvider(
                delay: 2,
                probe: supplementalProbe
            ),
            supplementalTimeout: .seconds(5)
        )
        let context = WeatherRefreshContext(
            location: location,
            requestBudgets: WeatherRequestBudgets(
                current: .milliseconds(150),
                weatherKit: .seconds(5)
            )
        )

        let start = ContinuousClock.now
        let updatesTask = Task {
            try await repository.updates(
                for: location,
                context: context,
                onUpdate: { update in
                    guard case .current(.unavailable) = update.event else { return }
                    currentUnavailable.fulfill()
                }
            )
        }

        await fulfillment(of: [currentUnavailable], timeout: 1)
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        let supplementalHadStarted = await supplementalProbe.hasStarted
        XCTAssertTrue(supplementalHadStarted)

        updatesTask.cancel()
        do {
            try await updatesTask.value
            XCTFail("Expected the parent refresh to cancel cleanly.")
        } catch is CancellationError {
            // Expected: the current product resolves before the owned refresh ends.
        }
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

    // MARK: - Live incremental path (`updates`), which the app uses

    func testUpdatesPrimaryCurrentWinsAsWholeGroup() async throws {
        var primaryCurrent = MockWeather.snapshot.current
        primaryCurrent.temperature = 51
        primaryCurrent.source.provider = .nwsObservation
        var fallback = MockWeather.snapshot.current
        fallback.temperature = 89
        fallback.source.provider = .weatherKit

        let updates = try await collectUpdates(LiveWeatherRepository(
            primary: FakePrimaryProvider(payload: PrimaryWeatherPayload(
                current: primaryCurrent,
                hourly: MockWeather.snapshot.hourly,
                daily: MockWeather.snapshot.daily,
                alerts: []
            )),
            supplemental: FakeSupplementalProvider(payload: SupplementalWeatherPayload(
                currentFallback: fallback,
                minutePrecipitation: MockWeather.snapshot.minutePrecipitation,
                solar: MockWeather.snapshot.solar
            ))
        ))

        let currents = updates.compactMap(\.currentState)
        XCTAssertEqual(currents.count, 1, "One current provider is selected per refresh.")
        XCTAssertEqual(currents.first?.value?.temperature, 51)
        XCTAssertEqual(currents.first?.value?.source.provider, .nwsObservation)
        XCTAssertTrue(updates.last?.isTerminal == true)
    }

    func testUpdatesMissingCurrentFromBothProvidersKeepsForecasts() async throws {
        let updates = try await collectUpdates(LiveWeatherRepository(
            primary: FakePrimaryProvider(payload: PrimaryWeatherPayload(
                current: nil,
                hourly: MockWeather.snapshot.hourly,
                daily: MockWeather.snapshot.daily,
                alerts: []
            )),
            supplemental: FakeSupplementalProvider(payload: SupplementalWeatherPayload(
                currentFallback: nil,
                minutePrecipitation: [],
                solar: nil
            ))
        ))

        let currents = updates.compactMap(\.currentState)
        XCTAssertEqual(currents.count, 1)
        XCTAssertNil(currents.first?.value)
        XCTAssertFalse(currents.first?.isLoading ?? true)
        XCTAssertTrue(updates.contains { update in
            guard case let .hourly(.available(items, _)) = update.event else { return false }
            return !items.isEmpty
        })
        XCTAssertTrue(updates.contains { update in
            guard case let .daily(.available(items, _)) = update.event else { return false }
            return !items.isEmpty
        })
    }

    func testFallbackArrivingAfterCurrentDeadlineStillReplacesUnavailable() async throws {
        var fallback = MockWeather.snapshot.current
        fallback.temperature = 66
        fallback.source.provider = .weatherKit
        let location = MockWeather.snapshot.location

        let updates = try await collectUpdates(
            LiveWeatherRepository(
                primary: FakePrimaryProvider(payload: PrimaryWeatherPayload(
                    current: nil,
                    hourly: MockWeather.snapshot.hourly,
                    daily: MockWeather.snapshot.daily,
                    alerts: []
                ), delay: .milliseconds(400)),
                supplemental: SlowSupplementalProvider(
                    payload: SupplementalWeatherPayload(
                        currentFallback: fallback,
                        minutePrecipitation: [],
                        solar: nil
                    ),
                    delay: .milliseconds(200)
                )
            ),
            context: WeatherRefreshContext(
                location: location,
                requestBudgets: WeatherRequestBudgets(
                    current: .milliseconds(50),
                    weatherKit: .seconds(5)
                )
            )
        )

        let currents = updates.compactMap(\.currentState)
        XCTAssertEqual(currents.count, 2, "Unavailable at the deadline, then the fallback.")
        XCTAssertNil(currents.first?.value)
        XCTAssertEqual(currents.last?.value?.temperature, 66)
        XCTAssertEqual(currents.last?.value?.source.provider, .weatherKit)
    }

    private func collectUpdates(
        _ repository: LiveWeatherRepository,
        context: WeatherRefreshContext? = nil
    ) async throws -> [WeatherProductUpdate] {
        let location = MockWeather.snapshot.location
        let context = context ?? WeatherRefreshContext(location: location)
        let recorder = RepositoryUpdateRecorder()
        try await repository.updates(for: location, context: context) { update in
            recorder.updates.append(update)
        }
        return recorder.updates
    }
}

private struct FakePrimaryProvider: PrimaryWeatherProviding {
    let payload: PrimaryWeatherPayload
    var delay: Duration = .zero

    func weather(for location: WeatherLocation) async throws -> PrimaryWeatherPayload {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return payload
    }
}

@MainActor
private final class RepositoryUpdateRecorder {
    var updates: [WeatherProductUpdate] = []
}

private extension WeatherProductUpdate {
    var currentState: WeatherProductState<CurrentConditions>? {
        guard case let .current(state) = event else { return nil }
        return state
    }

    var isTerminal: Bool {
        guard case .terminal = event else { return false }
        return true
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
