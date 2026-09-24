import XCTest
@testable import PlainSky

@MainActor
final class WeatherStoreTests: XCTestCase {
    func testLiveRefreshUsesFreshStateWithoutWritingLegacyWeatherCache() async throws {
        let suite = "WeatherStoreLiveCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        var legacyCached = MockWeather.snapshot
        legacyCached.current.temperature = -80
        preferences.saveCachedSnapshot(legacyCached)
        let store = WeatherStore(
            repository: PreviewWeatherRepository(),
            preferences: preferences,
            initialScreenState: WeatherScreenState(location: legacyCached.location),
            usesFreshOnlyState: true
        )

        await store.refresh()

        let cached = try XCTUnwrap(preferences.loadCachedSnapshot())
        XCTAssertEqual(cached.current.temperature, -80)
        XCTAssertNil(store.screenState.current.value)
        XCTAssertFalse(store.isShowingPlaceholderData)
    }

    func testForegroundExpiryUsesSourceValidityNotReuseCaps() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try freshOnlyStore(now: now)
        store.screenState.alerts = .available(
            [],
            WeatherValidationMetadata(provider: .nwsForecast, validatedAt: now.addingTimeInterval(-10 * 60))
        )
        store.screenState.current = nwsCurrent(
            validatedAt: now.addingTimeInterval(-10 * 60),
            observedAt: now.addingTimeInterval(-30 * 60)
        )

        XCTAssertFalse(store.expireProducts(at: now))
        XCTAssertNotNil(store.screenState.alerts.value, "A checked alert set stays while the app is open.")
        XCTAssertNotNil(store.screenState.current.value)

        store.screenState.current = nwsCurrent(
            validatedAt: now.addingTimeInterval(-10 * 60),
            observedAt: now.addingTimeInterval(-91 * 60)
        )
        XCTAssertTrue(store.expireProducts(at: now), "An aged-out observation must trigger a refresh.")
        XCTAssertNil(store.screenState.current.value)
    }

    func testForegroundExpiryRemovesIndividuallyExpiredAlerts() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try freshOnlyStore(now: now)
        let source = WeatherSourceMetadata(
            provider: .nwsForecast,
            productName: "NWS alerts",
            sourceName: nil,
            observedAt: nil,
            issuedAt: nil,
            validFrom: nil,
            validTo: nil,
            fetchedAt: now,
            expiresAt: nil,
            validatedAt: now
        )
        func alert(_ id: String, expiresAt: Date) -> WeatherAlert {
            WeatherAlert(
                id: id,
                event: "Heat Advisory",
                headline: id,
                severity: .moderate,
                effectiveAt: now.addingTimeInterval(-3600),
                expiresAt: expiresAt,
                description: "",
                instructions: nil,
                issuingOffice: nil,
                source: source
            )
        }
        store.screenState.alerts = .available(
            [alert("expired", expiresAt: now.addingTimeInterval(-1)),
             alert("active", expiresAt: now.addingTimeInterval(3600))],
            WeatherValidationMetadata(source: source, validatedAt: now)
        )

        store.expireProducts(at: now)

        XCTAssertEqual(store.screenState.alerts.value?.map(\.id), ["active"])
    }

    func testBriefResumeKeepsOnlyProductsInsideReuseCaps() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try freshOnlyStore(now: now)
        let validatedAt = now.addingTimeInterval(-2 * 60)
        store.screenState.alerts = .available(
            [],
            WeatherValidationMetadata(provider: .nwsForecast, validatedAt: validatedAt)
        )
        store.screenState.current = nwsCurrent(
            validatedAt: validatedAt,
            observedAt: now.addingTimeInterval(-20 * 60)
        )

        store.prepareForInactivity(at: now.addingTimeInterval(-60))
        store.prepareForActive(at: now)

        XCTAssertNotNil(store.screenState.current.value, "Current is inside its five-minute reuse cap.")
        XCTAssertTrue(
            store.screenState.alerts.isLoading,
            "Alerts past their sixty-second cap are rechecked, not shown or reported as failed."
        )
        XCTAssertFalse(store.isScreenMasked)
    }

    func testSameLocationRefreshKeepsFreshProductsUntilReplaced() async throws {
        let now = Date()
        let repository = HoldingUpdatesRepository()
        let store = try freshOnlyStore(now: now, repository: repository)
        store.screenState.current = nwsCurrent(
            validatedAt: now.addingTimeInterval(-60),
            observedAt: now.addingTimeInterval(-20 * 60)
        )

        let refresh = Task { await store.refresh(trigger: .manual) }
        await repository.waitUntilStarted()

        XCTAssertNotNil(store.screenState.current.value)
        XCTAssertTrue(store.screenState.hourly.isLoading)

        await repository.finish()
        await refresh.value
        XCTAssertNotNil(store.screenState.current.value)
        XCTAssertFalse(store.screenState.hourly.isLoading)
    }

    private func freshOnlyStore(
        now: Date,
        repository: (any WeatherRepository)? = nil
    ) throws -> WeatherStore {
        let suite = "WeatherStoreFreshnessTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let snapshot = MockWeather.snapshot
        return WeatherStore(
            repository: repository ?? PreviewWeatherRepository(),
            snapshot: snapshot,
            preferences: WeatherPreferences(defaults: defaults),
            initialScreenState: WeatherScreenState(location: snapshot.location),
            usesFreshOnlyState: true,
            freshnessPolicy: WeatherFreshnessPolicy(now: { now })
        )
    }

    private func nwsCurrent(
        validatedAt: Date,
        observedAt: Date
    ) -> WeatherProductState<CurrentConditions> {
        var current = MockWeather.snapshot.current
        current.source.provider = .nwsObservation
        current.source.observedAt = observedAt
        current.source.expiresAt = nil
        current.source.validatedAt = validatedAt
        return .available(current, WeatherValidationMetadata(source: current.source, validatedAt: validatedAt))
    }

    func testRefreshDoesNotCacheSnapshotByDefault() async throws {
        let suite = "WeatherStoreNoCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let store = WeatherStore(
            repository: PreviewWeatherRepository(),
            preferences: preferences
        )

        await store.refresh()

        XCTAssertNil(preferences.loadCachedSnapshot())
    }

    func testSelectingPlaceWithRecentCacheKeepsWeatherInLoadingState() throws {
        let suite = "WeatherStoreSelectCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let other = WeatherLocation(name: "Pensacola", region: "Florida", latitude: 30.4213, longitude: -87.2169)
        var cached = MockWeather.snapshot
        cached.location = other
        cached.current.temperature = 88
        preferences.saveCachedSnapshot(cached)

        let store = WeatherStore(
            repository: PreviewWeatherRepository(),
            preferences: preferences,
            initialScreenState: WeatherScreenState(location: MockWeather.snapshot.location),
            usesFreshOnlyState: true
        )

        store.select(other)

        XCTAssertEqual(store.screenState.location.id, other.id)
        XCTAssertNil(store.screenState.current.value)
        XCTAssertNil(store.screenState.hourly.value)
        XCTAssertNil(store.screenState.daily.value)
        XCTAssertNotEqual(store.snapshot.current.temperature, 88)
    }

    func testSelectingPlaceWithoutCacheStartsFreshLoadingState() throws {
        let suite = "WeatherStoreSelectNoCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WeatherStore(
            repository: PreviewWeatherRepository(),
            preferences: WeatherPreferences(defaults: defaults),
            initialScreenState: WeatherScreenState(location: MockWeather.snapshot.location),
            usesFreshOnlyState: true
        )

        store.select(WeatherLocation(name: "Elsewhere", region: "Ohio", latitude: 39.9, longitude: -83.0))

        XCTAssertTrue(store.screenState.current.isLoading)
        XCTAssertTrue(store.screenState.hourly.isLoading)
        XCTAssertTrue(store.screenState.daily.isLoading)
    }

    func testRestoringFromCacheDropsTimeSensitiveProducts() {
        let restored = MockWeather.snapshot.restoringFromCache()

        XCTAssertTrue(restored.minutePrecipitation.isEmpty)
        XCTAssertTrue(restored.alerts.isEmpty)
        XCTAssertNil(restored.solar)

        XCTAssertEqual(restored.availability(for: .alerts), .loading)
        XCTAssertEqual(restored.availability(for: .minutePrecipitation), .loading)
        XCTAssertEqual(restored.availability(for: .uvIndex), .loading)
        XCTAssertEqual(restored.availability(for: .solarEvents), .loading)

        XCTAssertFalse(restored.hourly.isEmpty)
        XCTAssertFalse(restored.daily.isEmpty)
    }

    func testRefreshIfNeededRunsWhileProductsAreStillLoading() async {
        let repository = CountingWeatherRepository()
        var snapshot = MockWeather.snapshot
        snapshot.fetchedAt = Date()
        snapshot.availability[.alerts] = .loading

        let store = WeatherStore(repository: repository, snapshot: snapshot)

        await store.refreshIfNeeded()

        XCTAssertEqual(repository.loadCount, 1)
    }

    func testRefreshIfNeededSkipsFreshSnapshotWithNoPendingProducts() async {
        let repository = CountingWeatherRepository()
        var snapshot = MockWeather.snapshot
        snapshot.fetchedAt = Date()

        let store = WeatherStore(repository: repository, snapshot: snapshot)

        await store.refreshIfNeeded()

        XCTAssertEqual(repository.loadCount, 0)
    }

    func testFailedRefreshResolvesPendingProductsToUnavailable() async {
        let store = WeatherStore(
            repository: FailingWeatherRepository(),
            snapshot: MockWeather.snapshot.restoringFromCache()
        )

        await store.refresh()

        let error = store.lastRefreshError
        XCTAssertNotNil(error)

        for product in [WeatherProduct.alerts, .minutePrecipitation, .uvIndex, .solarEvents] {
            XCTAssertFalse(
                store.snapshot.availability(for: product).isLoading,
                "\(product) should not stay in a loading state after a failed refresh."
            )
        }

        XCTAssertEqual(store.snapshot.availability(for: .alerts).message, error)
    }
}

@MainActor
private final class CountingWeatherRepository: WeatherRepository {
    private(set) var loadCount = 0

    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot {
        loadCount += 1

        var snapshot = MockWeather.snapshot
        snapshot.location = location
        await onPrimary(snapshot)
        return snapshot
    }
}

@MainActor
private struct FailingWeatherRepository: WeatherRepository {
    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot {
        throw ProviderError.notConfigured("NWS is unavailable in test.")
    }
}

private actor HoldingUpdatesRepository: WeatherRepository {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?

    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot {
        MockWeather.snapshot
    }

    func updates(
        for location: WeatherLocation,
        context: WeatherRefreshContext,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) async throws {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { release = $0 }

        let now = Date()
        var hourly = MockWeather.snapshot.hourly
        for index in hourly.indices {
            hourly[index].source.provider = .nwsForecast
            hourly[index].source.issuedAt = now
        }
        let source = hourly[0].source
        await onUpdate(WeatherProductUpdate(
            identity: context.identity,
            event: .hourly(.available(hourly, WeatherValidationMetadata(source: source, validatedAt: now)))
        ))
        await onUpdate(WeatherProductUpdate(identity: context.identity, event: .terminal))
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish() {
        release?.resume()
        release = nil
    }
}
