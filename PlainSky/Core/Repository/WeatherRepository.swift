import Foundation

protocol WeatherRepository {
    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot

    func updates(
        for location: WeatherLocation,
        context: WeatherRefreshContext,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) async throws
}

extension WeatherRepository {
    func load(location: WeatherLocation) async throws -> WeatherSnapshot {
        try await load(location: location, onPrimary: { _ in })
    }

    func updates(
        for location: WeatherLocation,
        context: WeatherRefreshContext,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) async throws {
        let snapshot = try await load(location: location) { partial in
            await publish(partial, identity: context.identity, onUpdate: onUpdate)
        }
        await publish(snapshot, identity: context.identity, onUpdate: onUpdate)
        await onUpdate(WeatherProductUpdate(
            identity: context.identity,
            event: .terminal
        ))
    }

    private func publish(
        _ snapshot: WeatherSnapshot,
        identity: WeatherRefreshIdentity,
        onUpdate: WeatherProductUpdateHandler
    ) async {
        let state = WeatherScreenState(preview: snapshot)
        await onUpdate(WeatherProductUpdate(identity: identity, event: .current(state.current)))
        await onUpdate(WeatherProductUpdate(identity: identity, event: .hourly(state.hourly)))
        await onUpdate(WeatherProductUpdate(identity: identity, event: .daily(state.daily)))
        await onUpdate(WeatherProductUpdate(identity: identity, event: .alerts(state.alerts)))
        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .minutePrecipitation(state.minutePrecipitation)
        ))
        await onUpdate(WeatherProductUpdate(identity: identity, event: .uvIndex(state.uvIndex)))
        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .solarEvents(state.solarEvents)
        ))
        await onUpdate(WeatherProductUpdate(identity: identity, event: .radar(state.radar)))
    }
}

struct PreviewWeatherRepository: WeatherRepository {
    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot {
        var snapshot = MockWeather.snapshot
        snapshot.location = location
        await onPrimary(snapshot)
        return snapshot
    }

    func updates(
        for location: WeatherLocation,
        context: WeatherRefreshContext,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) async throws {
        var snapshot = MockWeather.snapshot
        snapshot.location = location
        await onUpdate(WeatherProductUpdate(
            identity: context.identity,
            event: .current(WeatherScreenState(preview: snapshot).current)
        ))
        let state = WeatherScreenState(preview: snapshot)
        await onUpdate(WeatherProductUpdate(identity: context.identity, event: .hourly(state.hourly)))
        await onUpdate(WeatherProductUpdate(identity: context.identity, event: .daily(state.daily)))
        await onUpdate(WeatherProductUpdate(identity: context.identity, event: .alerts(state.alerts)))
        await onUpdate(WeatherProductUpdate(
            identity: context.identity,
            event: .minutePrecipitation(state.minutePrecipitation)
        ))
        await onUpdate(WeatherProductUpdate(identity: context.identity, event: .uvIndex(state.uvIndex)))
        await onUpdate(WeatherProductUpdate(
            identity: context.identity,
            event: .solarEvents(state.solarEvents)
        ))
        await onUpdate(WeatherProductUpdate(identity: context.identity, event: .radar(state.radar)))
        await onUpdate(WeatherProductUpdate(identity: context.identity, event: .terminal))
    }
}

final class LiveWeatherRepository: WeatherRepository {
    private let primary: any PrimaryWeatherProviding
    private let supplemental: any SupplementalWeatherProviding
    private let supplementalTimeout: Duration

    init(
        primary: any PrimaryWeatherProviding,
        supplemental: any SupplementalWeatherProviding,
        supplementalTimeout: Duration = .seconds(10)
    ) {
        self.primary = primary
        self.supplemental = supplemental
        self.supplementalTimeout = supplementalTimeout
    }

    func updates(
        for location: WeatherLocation,
        context: WeatherRefreshContext,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) async throws {
        try Task.checkCancellation()

        let coordinator = CurrentProviderSelection()
        let radarState: WeatherProductState<Void> = NOAARadarProvider.supports(location: location)
            ? .available(
                (),
                WeatherValidationMetadata(
                    provider: .noaaRadar,
                    validatedAt: context.startedAt
                )
            )
            : .unsupported("NOAA composite radar is not configured for this location.")
        await onUpdate(WeatherProductUpdate(
            identity: context.identity,
            event: .radar(radarState)
        ))
        let supplementalProviderTask = Task {
            try await supplemental.weather(for: location)
        }
        let supplementalDeadline = context.monotonicStart.advanced(by: context.requestBudgets.weatherKit)
        let currentDeadline = context.monotonicStart.advanced(by: context.requestBudgets.current)
        let currentDeadlineTask = Task {
            do {
                try await ContinuousClock().sleep(until: currentDeadline)
            } catch {
                return
            }
            if let state = await coordinator.currentDeadlineReached() {
                await onUpdate(WeatherProductUpdate(
                    identity: context.identity,
                    event: .current(state)
                ))
            }
        }
        defer { currentDeadlineTask.cancel() }

        let primaryTask = Task {
            do {
                try await primary.updates(
                    for: location,
                    context: context
                ) { update in
                    guard update.identity == context.identity else { return }

                    if case let .current(state) = update.event {
                        if let selected = await coordinator.receivedPrimary(state) {
                            await onUpdate(WeatherProductUpdate(
                                identity: context.identity,
                                sourceRevision: update.sourceRevision,
                                event: .current(selected)
                            ))
                        }
                    } else {
                        await onUpdate(update)
                    }
                }

                if let selected = await coordinator.primaryFinished() {
                    await onUpdate(WeatherProductUpdate(
                        identity: context.identity,
                        event: .current(selected)
                    ))
                }
            } catch is CancellationError {
                return
            } catch {
                await onUpdate(WeatherProductUpdate(
                    identity: context.identity,
                    event: .hourly(.unavailable("Unable to refresh the NWS hourly forecast."))
                ))
                await onUpdate(WeatherProductUpdate(
                    identity: context.identity,
                    event: .daily(.unavailable("Unable to refresh the NWS daily forecast."))
                ))
                await onUpdate(WeatherProductUpdate(
                    identity: context.identity,
                    event: .alerts(.unavailable("Unable to check National Weather Service alerts."))
                ))
                if let selected = await coordinator.primaryFailed() {
                    await onUpdate(WeatherProductUpdate(
                        identity: context.identity,
                        event: .current(selected)
                    ))
                }
            }
        }

        let supplementalTask = Task {
            let outcome: SupplementalOutcome
            do {
                outcome = .success(try await value(
                    of: supplementalProviderTask,
                    deadline: supplementalDeadline
                ))
            } catch is CancellationError {
                return
            } catch {
                outcome = .failure(failureMessage(for: error))
            }

            await emitSupplemental(
                outcome,
                location: location,
                identity: context.identity,
                onUpdate: onUpdate
            )
            if let selected = await coordinator.receivedSupplemental(outcome) {
                await onUpdate(WeatherProductUpdate(
                    identity: context.identity,
                    event: .current(selected)
                ))
            }
        }

        try await withTaskCancellationHandler {
            await primaryTask.value
            await supplementalTask.value
            try Task.checkCancellation()
        } onCancel: {
            currentDeadlineTask.cancel()
            primaryTask.cancel()
            supplementalProviderTask.cancel()
            supplementalTask.cancel()
        }

        await onUpdate(WeatherProductUpdate(
            identity: context.identity,
            event: .terminal
        ))
    }

    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot {
        try Task.checkCancellation()

        let supplementalTask = Task {
            try await supplemental.weather(for: location)
        }

        let primaryResult: PrimaryWeatherPayload
        do {
            primaryResult = try await primary.weather(for: location)
        } catch {
            supplementalTask.cancel()
            throw error
        }

        try Task.checkCancellation()

        if let primaryCurrent = primaryResult.current {
            let primarySnapshot = makeSnapshot(
                location: location,
                primaryResult: primaryResult,
                current: primaryCurrent,
                supplementalOutcome: .loading
            )
            await onPrimary(primarySnapshot)

            try Task.checkCancellation()

            let outcome = try await supplementalOutcome(from: supplementalTask)

            try Task.checkCancellation()

            return makeSnapshot(
                location: location,
                primaryResult: primaryResult,
                current: primaryCurrent,
                supplementalOutcome: outcome
            )
        }

        let outcome = try await supplementalOutcome(from: supplementalTask)
        try Task.checkCancellation()

        switch outcome {
        case let .success(payload):
            guard let fallback = payload.currentFallback else {
                throw missingCurrentError
            }

            return makeSnapshot(
                location: location,
                primaryResult: primaryResult,
                current: fallback,
                supplementalOutcome: .success(payload)
            )

        case .failure, .loading:
            throw missingCurrentError
        }
    }

    private func makeSnapshot(
        location: WeatherLocation,
        primaryResult: PrimaryWeatherPayload,
        current: CurrentConditions,
        supplementalOutcome: SupplementalOutcome
    ) -> WeatherSnapshot {
        var availability = primaryResult.availability

        if availability[.currentConditions] == nil {
            availability[.currentConditions] = .available
        }
        if availability[.hourlyForecast] == nil {
            availability[.hourlyForecast] = primaryResult.hourly.isEmpty
                ? .unavailable("Hourly forecast data is currently unavailable.")
                : .available
        }
        if availability[.dailyForecast] == nil {
            availability[.dailyForecast] = primaryResult.daily.isEmpty
                ? .unavailable("Daily forecast data is currently unavailable.")
                : .available
        }
        if availability[.alerts] == nil {
            availability[.alerts] = .available
        }

        let supplementalProducts: [WeatherProduct] = [
            .minutePrecipitation,
            .uvIndex,
            .solarEvents
        ]

        switch supplementalOutcome {
        case .loading:
            for product in supplementalProducts {
                availability[product] = .loading
            }

        case let .failure(message):
            for product in supplementalProducts {
                availability[product] = .unavailable(message)
            }

        case let .success(payload):
            availability.merge(payload.availability) { _, supplemental in
                supplemental
            }

            if availability[.minutePrecipitation] == nil {
                availability[.minutePrecipitation] = payload.minutePrecipitation.isEmpty
                    ? .unsupported("Next-hour precipitation is not available for this location.")
                    : .available
            }

            if availability[.uvIndex] == nil {
                availability[.uvIndex] = payload.solar?.uvIndex == nil
                    ? .unsupported("UV data is not available for this location.")
                    : .available
            }

            if availability[.solarEvents] == nil {
                let hasSolarEvent = payload.solar?.sunrise != nil
                    || payload.solar?.sunset != nil
                availability[.solarEvents] = hasSolarEvent
                    ? .available
                    : .unsupported("Sunrise and sunset data is not available for this location.")
            }
        }

        if availability[.radar] == nil {
            availability[.radar] = NOAARadarProvider.supports(location: location)
                ? .available
                : .unsupported("NOAA composite radar is not configured for this location.")
        }

        let supplementalPayload: SupplementalWeatherPayload?
        if case let .success(payload) = supplementalOutcome {
            supplementalPayload = payload
        } else {
            supplementalPayload = nil
        }

        return WeatherSnapshot(
            location: location,
            current: current,
            hourly: primaryResult.hourly,
            daily: primaryResult.daily,
            minutePrecipitation: supplementalPayload?.minutePrecipitation ?? [],
            alerts: primaryResult.alerts,
            solar: supplementalPayload?.solar,
            availability: availability,
            fetchedAt: Date()
        )
    }

    private func supplementalOutcome(
        from task: Task<SupplementalWeatherPayload, Error>
    ) async throws -> SupplementalOutcome {
        do {
            return .success(try await value(of: task))
        } catch is CancellationError {
            task.cancel()
            throw CancellationError()
        } catch {
            task.cancel()
            return .failure(failureMessage(for: error))
        }
    }

    private func value(
        of task: Task<SupplementalWeatherPayload, Error>,
        deadline: ContinuousClock.Instant? = nil
    ) async throws -> SupplementalWeatherPayload {
        let timeout: Duration
        if let deadline {
            timeout = ContinuousClock().now.duration(to: deadline)
            guard timeout > .zero else {
                task.cancel()
                throw SupplementalTimeoutError()
            }
        } else {
            timeout = supplementalTimeout
        }
        let resolver = SupplementalRaceResolver()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard resolver.install(continuation) else { return }

                let timer = Task {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }

                    task.cancel()
                    resolver.finish(
                        with: .failure(SupplementalTimeoutError())
                    )
                }

                let waiter = Task {
                    let result: Result<SupplementalWeatherPayload, Error>

                    do {
                        result = .success(try await task.value)
                    } catch {
                        result = .failure(error)
                    }

                    resolver.finish(with: result)
                }

                resolver.attach(timer: timer, waiter: waiter)
            }
        } onCancel: {
            task.cancel()
            resolver.cancel()
        }
    }

    private func emitSupplemental(
        _ outcome: SupplementalOutcome,
        location: WeatherLocation,
        identity: WeatherRefreshIdentity,
        onUpdate: WeatherProductUpdateHandler
    ) async {
        let state: WeatherScreenState
        switch outcome {
        case .loading:
            return
        case let .failure(message):
            var snapshot = MockWeather.snapshot
            snapshot.location = location
            snapshot.minutePrecipitation = []
            snapshot.solar = nil
            snapshot.availability[.minutePrecipitation] = .unavailable(message)
            snapshot.availability[.uvIndex] = .unavailable(message)
            snapshot.availability[.solarEvents] = .unavailable(message)
            state = WeatherScreenState(preview: snapshot)
        case let .success(payload):
            var availability = payload.availability
            if availability[.minutePrecipitation] == nil {
                availability[.minutePrecipitation] = payload.minutePrecipitation.isEmpty
                    ? .unsupported("Next-hour precipitation is not available for this location.")
                    : .available
            }
            if availability[.uvIndex] == nil {
                availability[.uvIndex] = payload.solar?.uvIndex == nil
                    ? .unsupported("UV data is not available for this location.")
                    : .available
            }
            if availability[.solarEvents] == nil {
                let hasSolarEvent = payload.solar?.sunrise != nil || payload.solar?.sunset != nil
                availability[.solarEvents] = hasSolarEvent
                    ? .available
                    : .unsupported("Sunrise and sunset data is not available for this location.")
            }

            var current = payload.currentFallback ?? MockWeather.snapshot.current
            current.source.validatedAt = Date()
            let snapshot = WeatherSnapshot(
                location: location,
                current: current,
                hourly: [],
                daily: [],
                minutePrecipitation: payload.minutePrecipitation,
                alerts: [],
                solar: payload.solar,
                availability: availability,
                fetchedAt: Date()
            )
            state = WeatherScreenState(preview: snapshot)
        }

        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .minutePrecipitation(state.minutePrecipitation)
        ))
        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .uvIndex(state.uvIndex)
        ))
        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .solarEvents(state.solarEvents)
        ))
    }

    private func failureMessage(for error: Error) -> String {
        if let providerError = error as? ProviderError {
            return providerError.localizedDescription
        }

        if error is SupplementalTimeoutError || error is CancellationError {
            return "Supplemental weather did not respond in time. It will retry on the next refresh."
        }

        return "Supplemental weather is temporarily unavailable."
    }

    private var missingCurrentError: ProviderError {
        .missingRequiredData(
            "Neither the NWS observation group nor the approved current-conditions fallback was available."
        )
    }
}

/// Chooses one current-conditions group per refresh. NWS wins when it returns a
/// usable observation before its deadline; the WeatherKit group is used only
/// after NWS has failed or timed out. Fields are never mixed across providers.
private actor CurrentProviderSelection {
    private var didFinishPrimary = false
    private var supplementalFinished = false
    private var didResolveCurrent = false
    private var didReachPrimaryDeadline = false
    private var fallback: CurrentConditions?
    private var supplementalFailure: String?

    func receivedPrimary(
        _ state: WeatherProductState<CurrentConditions>
    ) -> WeatherProductState<CurrentConditions>? {
        guard !didResolveCurrent else { return nil }
        switch state {
        case .loading:
            return nil
        case .available:
            // A late NWS observation after its deadline is ignored so the
            // selected provider cannot flicker within one refresh.
            guard !didReachPrimaryDeadline else { return nil }
            didFinishPrimary = true
            didResolveCurrent = true
            return state
        case .unsupported, .unavailable:
            didFinishPrimary = true
            return resolveIfReady()
        }
    }

    func primaryFinished() -> WeatherProductState<CurrentConditions>? {
        guard !didResolveCurrent else { return nil }
        didFinishPrimary = true
        return resolveIfReady()
    }

    func primaryFailed() -> WeatherProductState<CurrentConditions>? {
        primaryFinished()
    }

    func receivedSupplemental(
        _ outcome: SupplementalOutcome
    ) -> WeatherProductState<CurrentConditions>? {
        guard !didResolveCurrent else { return nil }
        supplementalFinished = true
        switch outcome {
        case .loading:
            return nil
        case let .success(payload):
            fallback = payload.currentFallback
        case let .failure(message):
            supplementalFailure = message
        }
        // After the deadline the product already reads as unavailable; only a
        // usable fallback changes what is shown.
        if didReachPrimaryDeadline, fallback == nil {
            didResolveCurrent = true
            return nil
        }
        return resolveIfReady()
    }

    /// Stops waiting for NWS. The product becomes unavailable immediately so
    /// its section does not spin past the budget, but a fresh approved
    /// fallback that is still in flight may replace that state when it lands.
    func currentDeadlineReached() -> WeatherProductState<CurrentConditions>? {
        guard !didResolveCurrent, !didReachPrimaryDeadline else { return nil }
        didReachPrimaryDeadline = true
        didFinishPrimary = true
        if let resolved = resolveIfReady() {
            return resolved
        }
        return .unavailable(
            "No fresh usable current conditions were available within the refresh budget."
        )
    }

    private func resolveIfReady() -> WeatherProductState<CurrentConditions>? {
        guard didFinishPrimary else { return nil }
        if let fallback {
            didResolveCurrent = true
            return .available(
                fallback,
                WeatherValidationMetadata(
                    source: fallback.source,
                    validatedAt: Date()
                )
            )
        }
        guard supplementalFinished else { return nil }
        didResolveCurrent = true
        return .unavailable(
            supplementalFailure
                ?? "No fresh usable current conditions were available from the approved providers."
        )
    }
}

private enum SupplementalOutcome: Sendable {
    case loading
    case success(SupplementalWeatherPayload)
    case failure(String)
}

private final class SupplementalRaceResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SupplementalWeatherPayload, Error>?
    private var pendingResult: Result<SupplementalWeatherPayload, Error>?
    private var timer: Task<Void, Never>?
    private var waiter: Task<Void, Never>?
    private var hasFinished = false

    func install(
        _ continuation: CheckedContinuation<SupplementalWeatherPayload, Error>
    ) -> Bool {
        lock.lock()
        guard !hasFinished else {
            let result = pendingResult ?? .failure(CancellationError())
            pendingResult = nil
            lock.unlock()
            continuation.resume(with: result)
            return false
        }

        self.continuation = continuation
        lock.unlock()
        return true
    }

    func attach(
        timer: Task<Void, Never>,
        waiter: Task<Void, Never>
    ) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            timer.cancel()
            waiter.cancel()
            return
        }

        self.timer = timer
        self.waiter = waiter
        lock.unlock()
    }

    func cancel() {
        finish(with: .failure(CancellationError()))
    }

    func finish(
        with result: Result<SupplementalWeatherPayload, Error>
    ) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }

        hasFinished = true
        pendingResult = continuation == nil ? result : nil
        let continuation = self.continuation
        self.continuation = nil
        let timer = self.timer
        self.timer = nil
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()

        timer?.cancel()
        waiter?.cancel()
        continuation?.resume(with: result)
    }
}

private struct SupplementalTimeoutError: Error {}
