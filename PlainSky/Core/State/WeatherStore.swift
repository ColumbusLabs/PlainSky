import Observation
import SwiftUI

@MainActor
@Observable
final class WeatherStore {
    var snapshot: WeatherSnapshot
    var screenState: WeatherScreenState
    var savedLocations: [WeatherLocation]
    var isRefreshing = false
    private(set) var isRefreshInFlight = false
    var isScreenMasked = false
    var lastRefreshError: String?
    var isShowingPlaceholderData: Bool

    var unitSystem: WeatherUnitSystem {
        didSet {
            preferences.saveUnitSystem(unitSystem)
        }
    }

    private let repository: any WeatherRepository
    private let preferences: WeatherPreferences
    private let usesFreshOnlyState: Bool
    private let freshnessPolicy: WeatherFreshnessPolicy
    private var loadGeneration = 0
    private var activeLoad: Task<Void, Never>?
    private var inactiveAt: Date?
    private var pendingSolarEvents: WeatherProductState<SolarWeather>?
    private var didMarkFirstFreshSection = false
    private var didMarkFreshCurrent = false
    private var didMarkCoreCompletion = false

    init(
        repository: (any WeatherRepository)? = nil,
        snapshot: WeatherSnapshot = MockWeather.snapshot,
        savedLocations: [WeatherLocation]? = nil,
        preferences: WeatherPreferences? = nil,
        isShowingPlaceholderData: Bool = false,
        initialScreenState: WeatherScreenState? = nil,
        usesFreshOnlyState: Bool = false,
        freshnessPolicy: WeatherFreshnessPolicy = WeatherFreshnessPolicy()
    ) {
        let resolvedPreferences = preferences ?? .live

        self.repository = repository ?? PreviewWeatherRepository()
        self.preferences = resolvedPreferences
        self.isShowingPlaceholderData = isShowingPlaceholderData
        self.usesFreshOnlyState = usesFreshOnlyState
        self.freshnessPolicy = freshnessPolicy
        self.unitSystem = resolvedPreferences.loadUnitSystem() ?? .us
        self.savedLocations = savedLocations
            ?? resolvedPreferences.loadSavedLocations()
            ?? MockWeather.savedLocations

        var initialSnapshot = snapshot
        if let lastLocation = resolvedPreferences.loadLastLocation() {
            initialSnapshot.location = lastLocation
        }
        self.snapshot = initialSnapshot
        self.screenState = initialScreenState ?? WeatherScreenState(preview: initialSnapshot)
    }

    func refreshIfNeeded(
        maxAge: TimeInterval = 10 * 60,
        trigger: WeatherRefreshTrigger = .automatic
    ) async {
        guard !isRefreshInFlight else { return }

        if usesFreshOnlyState {
            let now = freshnessPolicy.now()
            let coreIsFresh = freshnessPolicy.isFresh(
                screenState.current.validation ?? .unvalidated,
                for: .currentConditions,
                now: now
            ) && freshnessPolicy.isFresh(
                screenState.hourly.validation ?? .unvalidated,
                for: .hourlyForecast,
                now: now
            ) && freshnessPolicy.isFresh(
                screenState.daily.validation ?? .unvalidated,
                for: .dailyForecast,
                now: now
            ) && freshnessPolicy.isFresh(
                screenState.alerts.validation ?? .unvalidated,
                for: .alerts,
                now: now
            )

            guard !coreIsFresh else { return }
            await refresh(trigger: trigger)
            return
        }

        let age = Date().timeIntervalSince(snapshot.fetchedAt)
        let hasPendingProducts = snapshot.availability.values
            .contains { $0.isLoading }

        guard age >= maxAge || hasPendingProducts else { return }

        await refresh(trigger: trigger)
    }

    func refresh(trigger: WeatherRefreshTrigger = .manual) async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedLocation = snapshot.location

        activeLoad?.cancel()

        let context = WeatherRefreshContext(
            location: requestedLocation,
            now: freshnessPolicy.now(),
            trigger: trigger
        )
        didMarkFirstFreshSection = false
        didMarkFreshCurrent = false
        didMarkCoreCompletion = false
        pendingSolarEvents = nil
        switch trigger {
        case .startup:
            WeatherInstrumentation.mark("Weather refresh startup")
        case .foreground:
            WeatherInstrumentation.mark("Weather refresh foreground resume")
        case .manual:
            WeatherInstrumentation.mark("Weather refresh manual")
        case .locationChange:
            WeatherInstrumentation.mark("Weather refresh location change")
        case .automatic:
            WeatherInstrumentation.mark("Weather refresh automatic")
        }
        isRefreshInFlight = true
        let previous = screenState
        screenState.beginRefresh(context)
        if usesFreshOnlyState,
           WeatherRequestLocationKey(previous.location) == context.identity.locationKey {
            retainReusableProducts(from: previous, now: context.startedAt)
        }

        let load = Task {
            await performRefresh(
                generation: generation,
                location: requestedLocation,
                context: context
            )
        }
        activeLoad = load
        await load.value
        if generation == loadGeneration {
            activeLoad = nil
        }
    }

    private func performRefresh(
        generation: Int,
        location requestedLocation: WeatherLocation,
        context: WeatherRefreshContext
    ) async {
        guard generation == loadGeneration else { return }

        isRefreshing = true
        lastRefreshError = nil

        do {
            try await repository.updates(
                for: requestedLocation,
                context: context
            ) { update in
                guard generation == self.loadGeneration else { return }
                self.apply(update)
            }

            try Task.checkCancellation()
        } catch {
            guard generation == loadGeneration else { return }
            lastRefreshError = error.localizedDescription
            resolvePendingProducts(with: error.localizedDescription)
        }

        if generation == loadGeneration {
            isRefreshing = false
            isRefreshInFlight = false
            activeLoad = nil
        }
    }

    func select(_ location: WeatherLocation) {
        let changedLocation = WeatherRequestLocationKey(screenState.location)
            != WeatherRequestLocationKey(location)
        invalidateOutstandingLoad()

        if changedLocation {
            pendingSolarEvents = nil
            if usesFreshOnlyState {
                screenState = WeatherScreenState(location: location)
                isShowingPlaceholderData = false
                lastRefreshError = nil
            } else {
                var preview = snapshot
                preview.location = location
                screenState = WeatherScreenState(preview: preview)
            }
        } else {
            screenState.location = location
        }

        snapshot.location = location
        preferences.saveLastLocation(location)
    }

    func selectAndRefresh(_ location: WeatherLocation) {
        select(location)
        Task {
            await refresh(trigger: .locationChange)
        }
    }

    func setCurrentLocation(_ location: WeatherLocation) {
        var location = location
        location.isCurrentLocation = true

        if let index = savedLocations.firstIndex(where: { $0.isCurrentLocation }) {
            savedLocations[index] = location
            if index != 0 {
                let updated = savedLocations.remove(at: index)
                savedLocations.insert(updated, at: 0)
            }
        } else {
            savedLocations.insert(location, at: 0)
        }

        persistLocations()
        select(location)
    }

    func setCurrentLocationAndRefresh(_ location: WeatherLocation) {
        setCurrentLocation(location)
        Task {
            await refresh(trigger: .locationChange)
        }
    }

    func addLocation(_ location: WeatherLocation) {
        if let existing = savedLocations.first(where: {
            abs($0.latitude - location.latitude) < 0.001 &&
            abs($0.longitude - location.longitude) < 0.001
        }) {
            select(existing)
            return
        }

        savedLocations.append(location)
        persistLocations()
        select(location)
    }

    func addLocationAndRefresh(_ location: WeatherLocation) {
        addLocation(location)
        Task {
            await refresh(trigger: .locationChange)
        }
    }

    func renameLocation(_ location: WeatherLocation, to proposedName: String) {
        guard !location.isCurrentLocation,
              let index = savedLocations.firstIndex(where: { $0.id == location.id }) else {
            return
        }

        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        savedLocations[index].name = trimmed
        let renamed = savedLocations[index]
        persistLocations()

        if snapshot.location.id == renamed.id {
            snapshot.location = renamed
            screenState.location = renamed
            preferences.saveLastLocation(renamed)
        }
    }

    func canMoveLocation(_ location: WeatherLocation, offset: Int) -> Bool {
        guard !location.isCurrentLocation,
              let index = savedLocations.firstIndex(where: { $0.id == location.id }) else {
            return false
        }

        let target = index + offset
        guard savedLocations.indices.contains(target) else { return false }

        return !savedLocations[target].isCurrentLocation
    }

    func moveLocation(_ location: WeatherLocation, offset: Int) {
        guard canMoveLocation(location, offset: offset),
              let index = savedLocations.firstIndex(where: { $0.id == location.id }) else {
            return
        }

        savedLocations.swapAt(index, index + offset)
        persistLocations()
    }

    func removeLocation(_ location: WeatherLocation) {
        guard !location.isCurrentLocation else { return }

        let wasSelected = snapshot.location.id == location.id
        savedLocations.removeAll { $0.id == location.id }
        persistLocations()

        if wasSelected, let fallback = savedLocations.first {
            selectAndRefresh(fallback)
        }
    }

    func clearRefreshError() {
        lastRefreshError = nil
    }

    private func invalidateOutstandingLoad() {
        activeLoad?.cancel()
        activeLoad = nil
        loadGeneration += 1
        isRefreshing = false
        isRefreshInFlight = false
    }

    func prepareForInactivity(at date: Date? = nil) {
        inactiveAt = date ?? freshnessPolicy.now()
        isScreenMasked = true
    }

    func prepareForActive(at date: Date? = nil) {
        let now = date ?? freshnessPolicy.now()
        if let inactiveAt, freshnessPolicy.isLongResume(since: inactiveAt, now: now) {
            invalidateOutstandingLoad()
            pendingSolarEvents = nil
            screenState = WeatherScreenState(location: screenState.location)
            isShowingPlaceholderData = false
            lastRefreshError = nil
        } else if usesFreshOnlyState {
            // A brief interruption keeps only products still inside their reuse
            // caps. The rest show as loading because the activation refresh
            // that follows will check them again.
            let previous = screenState
            screenState.clearWeather()
            screenState.identity = previous.identity
            screenState.routeRevision = previous.routeRevision
            screenState.timeZoneIdentifier = previous.timeZoneIdentifier
            screenState.radar = previous.radar
            retainReusableProducts(from: previous, now: now)
        }
        inactiveAt = nil
        isScreenMasked = false
    }

    /// Ages values out while the app stays in the foreground, using each
    /// product's source validity. Returns true when a product that was showing
    /// a value no longer has one, so the caller can start a refresh.
    @discardableResult
    func expireProducts(at date: Date? = nil) -> Bool {
        guard usesFreshOnlyState else { return false }
        let now = date ?? freshnessPolicy.now()
        let before = screenState

        if case let .available(alerts, metadata) = screenState.alerts {
            let active = alerts.filter { alert in
                alert.expiresAt.map { $0 > now } ?? true
            }
            if active.count != alerts.count {
                screenState.alerts = .available(active, metadata)
                snapshot.alerts = active
            }
        }

        screenState.current = freshnessPolicy.refreshedState(
            screenState.current,
            for: .currentConditions,
            now: now,
            scope: .display
        )
        screenState.hourly = freshnessPolicy.refreshedState(
            screenState.hourly,
            for: .hourlyForecast,
            now: now,
            scope: .display
        )
        screenState.daily = freshnessPolicy.refreshedState(
            screenState.daily,
            for: .dailyForecast,
            now: now,
            scope: .display
        )
        screenState.alerts = freshnessPolicy.refreshedState(
            screenState.alerts,
            for: .alerts,
            now: now,
            scope: .display
        )
        screenState.minutePrecipitation = freshnessPolicy.refreshedState(
            screenState.minutePrecipitation,
            for: .minutePrecipitation,
            now: now,
            scope: .display
        )
        screenState.uvIndex = freshnessPolicy.refreshedState(
            screenState.uvIndex,
            for: .uvIndex,
            now: now,
            scope: .display
        )
        screenState.solarEvents = freshnessPolicy.refreshedState(
            screenState.solarEvents,
            for: .solarEvents,
            now: now,
            timeZoneIdentifier: screenState.timeZoneIdentifier,
            scope: .display
        )

        return (before.current.value != nil && screenState.current.value == nil)
            || (before.hourly.value != nil && screenState.hourly.value == nil)
            || (before.daily.value != nil && screenState.daily.value == nil)
            || (before.alerts.value != nil && screenState.alerts.value == nil)
            || (before.minutePrecipitation.value != nil && screenState.minutePrecipitation.value == nil)
            || (before.uvIndex.value != nil && screenState.uvIndex.value == nil)
            || (before.solarEvents.value != nil && screenState.solarEvents.value == nil)
    }

    /// Copies products from `previous` that are still inside their reuse caps.
    /// Everything else keeps the loading state it was reset to.
    private func retainReusableProducts(from previous: WeatherScreenState, now: Date) {
        func reusable<Value>(
            _ state: WeatherProductState<Value>,
            _ product: WeatherProduct
        ) -> Bool {
            guard let validation = state.validation else { return false }
            return freshnessPolicy.isFresh(
                validation,
                for: product,
                now: now,
                timeZoneIdentifier: previous.timeZoneIdentifier
            )
        }

        if reusable(previous.current, .currentConditions) { screenState.current = previous.current }
        if reusable(previous.hourly, .hourlyForecast) { screenState.hourly = previous.hourly }
        if reusable(previous.daily, .dailyForecast) { screenState.daily = previous.daily }
        if reusable(previous.alerts, .alerts) { screenState.alerts = previous.alerts }
        if reusable(previous.minutePrecipitation, .minutePrecipitation) {
            screenState.minutePrecipitation = previous.minutePrecipitation
        }
        if reusable(previous.uvIndex, .uvIndex) { screenState.uvIndex = previous.uvIndex }
        if reusable(previous.solarEvents, .solarEvents) {
            screenState.solarEvents = previous.solarEvents
            if screenState.timeZoneIdentifier == nil {
                screenState.timeZoneIdentifier = previous.timeZoneIdentifier
            }
        }
    }

    private func resolvePendingProducts(with message: String) {
        let pendingProducts = snapshot.availability
            .filter { $0.value.isLoading }
            .map(\.key)

        guard !pendingProducts.isEmpty else { return }

        var updated = snapshot
        for product in pendingProducts {
            updated.availability[product] = .unavailable(message)
        }
        snapshot = updated

        if screenState.current.isLoading {
            screenState.current = .unavailable(message)
        }
        if screenState.hourly.isLoading {
            screenState.hourly = .unavailable(message)
        }
        if screenState.daily.isLoading {
            screenState.daily = .unavailable(message)
        }
        if screenState.alerts.isLoading {
            screenState.alerts = .unavailable(message)
        }
        if screenState.minutePrecipitation.isLoading {
            screenState.minutePrecipitation = .unavailable(message)
        }
        if screenState.uvIndex.isLoading {
            screenState.uvIndex = .unavailable(message)
        }
        if screenState.solarEvents.isLoading {
            screenState.solarEvents = .unavailable(message)
        }
    }

    private func persistLocations() {
        preferences.saveSavedLocations(savedLocations)
    }

    private func apply(
        _ update: WeatherProductUpdate
    ) {
        guard isRefreshInFlight,
              update.identity == screenState.identity,
              update.identity.locationKey == WeatherRequestLocationKey(screenState.location) else {
            return
        }

        let now = freshnessPolicy.now()
        switch update.event {
        case let .routeRevision(revision, timeZoneIdentifier):
            // Forecasts from a superseded grid route are discarded; the provider
            // refetches them on the new route. Current conditions come from a
            // station observation and remain valid across a grid remapping.
            if let currentRevision = screenState.routeRevision,
               currentRevision != revision {
                screenState.hourly = .loading
                screenState.daily = .loading
                snapshot.availability[.hourlyForecast] = .loading
                snapshot.availability[.dailyForecast] = .loading
            }
            screenState.routeRevision = revision
            screenState.timeZoneIdentifier = timeZoneIdentifier
            if let pendingSolarEvents, let timeZoneIdentifier {
                self.pendingSolarEvents = nil
                let state = freshnessPolicy.refreshedState(
                    pendingSolarEvents,
                    for: .solarEvents,
                    now: now,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                screenState.solarEvents = state
                snapshot.solar = state.value
                snapshot.availability[.solarEvents] = state.availability
            }

        case let .current(incoming):
            let state = usesFreshOnlyState
                ? freshnessPolicy.refreshedState(incoming, for: .currentConditions, now: now)
                : incoming
            screenState.current = state
            snapshot.availability[.currentConditions] = state.availability
            if let value = state.value {
                snapshot.current = value
                isShowingPlaceholderData = false
                isRefreshing = false
            }

        case let .hourly(incoming):
            guard acceptsRouteRevision(update.sourceRevision) else { return }
            let state = usesFreshOnlyState
                ? freshnessPolicy.refreshedState(incoming, for: .hourlyForecast, now: now)
                : incoming
            screenState.hourly = state
            snapshot.availability[.hourlyForecast] = state.availability
            if let value = state.value {
                snapshot.hourly = value
                isShowingPlaceholderData = false
                isRefreshing = false
            }

        case let .daily(incoming):
            guard acceptsRouteRevision(update.sourceRevision) else { return }
            let state = usesFreshOnlyState
                ? freshnessPolicy.refreshedState(incoming, for: .dailyForecast, now: now)
                : incoming
            screenState.daily = state
            snapshot.availability[.dailyForecast] = state.availability
            if let value = state.value {
                snapshot.daily = value
                isShowingPlaceholderData = false
                isRefreshing = false
            }

        case let .alerts(incoming):
            let state = usesFreshOnlyState
                ? freshnessPolicy.refreshedState(incoming, for: .alerts, now: now)
                : incoming
            screenState.alerts = state
            snapshot.availability[.alerts] = state.availability
            if let value = state.value {
                snapshot.alerts = value
            }

        case let .minutePrecipitation(incoming):
            let state = usesFreshOnlyState
                ? freshnessPolicy.refreshedState(incoming, for: .minutePrecipitation, now: now)
                : incoming
            screenState.minutePrecipitation = state
            snapshot.availability[.minutePrecipitation] = state.availability
            if let value = state.value {
                snapshot.minutePrecipitation = value
            }

        case let .uvIndex(incoming):
            let state = usesFreshOnlyState
                ? freshnessPolicy.refreshedState(incoming, for: .uvIndex, now: now)
                : incoming
            screenState.uvIndex = state
            snapshot.availability[.uvIndex] = state.availability

        case let .solarEvents(incoming):
            if usesFreshOnlyState,
               case .available = incoming,
               screenState.timeZoneIdentifier == nil {
                pendingSolarEvents = incoming
                return
            }
            pendingSolarEvents = nil
            let state = usesFreshOnlyState
                ? freshnessPolicy.refreshedState(
                    incoming,
                    for: .solarEvents,
                    now: now,
                    timeZoneIdentifier: screenState.timeZoneIdentifier
                )
                : incoming
            screenState.solarEvents = state
            snapshot.availability[.solarEvents] = state.availability
            snapshot.solar = state.value

        case let .radar(state):
            screenState.radar = state
            snapshot.availability[.radar] = state.availability

        case .terminal:
            if pendingSolarEvents != nil {
                pendingSolarEvents = nil
                screenState.solarEvents = .unavailable(
                    "The local date for sunrise and sunset could not be verified."
                )
                snapshot.availability[.solarEvents] = screenState.solarEvents.availability
            }
            resolvePendingProducts(with: "This weather product did not return a usable result.")
            isRefreshInFlight = false
            isRefreshing = false
            activeLoad = nil
            if !didMarkCoreCompletion {
                didMarkCoreCompletion = true
                WeatherInstrumentation.mark("Weather core products complete")
            }
            WeatherInstrumentation.mark("Weather owned refresh complete")
        }
        markFreshnessMilestones()
    }

    private func acceptsRouteRevision(_ revision: String?) -> Bool {
        guard let revision else { return true }
        if let currentRevision = screenState.routeRevision,
           currentRevision != revision {
            return false
        }
        if screenState.routeRevision == nil {
            screenState.routeRevision = revision
        }
        return true
    }

    private func markFreshnessMilestones() {
        guard usesFreshOnlyState else { return }
        let hasFreshSection = [
            screenState.current.availability,
            screenState.hourly.availability,
            screenState.daily.availability,
            screenState.alerts.availability,
            screenState.minutePrecipitation.availability,
            screenState.uvIndex.availability,
            screenState.solarEvents.availability
        ].contains(.available)
        if hasFreshSection, !didMarkFirstFreshSection {
            didMarkFirstFreshSection = true
            WeatherInstrumentation.mark("First fresh weather section")
        }
        if screenState.current.availability == .available, !didMarkFreshCurrent {
            didMarkFreshCurrent = true
            WeatherInstrumentation.mark("First fresh current conditions")
        }

        let coreProductsResolved = !screenState.current.isLoading
            && !screenState.hourly.isLoading
            && !screenState.daily.isLoading
            && !screenState.alerts.isLoading
        if coreProductsResolved, !didMarkCoreCompletion {
            didMarkCoreCompletion = true
            WeatherInstrumentation.mark("Weather core products complete")
        }
    }
}

private extension WeatherValidationMetadata {
    static let unvalidated = WeatherValidationMetadata(
        provider: .mock,
        validatedAt: .distantPast
    )
}
