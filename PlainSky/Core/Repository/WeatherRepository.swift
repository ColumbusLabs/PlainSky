import Foundation

@MainActor
protocol WeatherRepository {
    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot
}

extension WeatherRepository {
    func load(location: WeatherLocation) async throws -> WeatherSnapshot {
        try await load(location: location, onPrimary: { _ in })
    }
}

@MainActor
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
}

@MainActor
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
        of task: Task<SupplementalWeatherPayload, Error>
    ) async throws -> SupplementalWeatherPayload {
        let timeout = supplementalTimeout
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

private enum SupplementalOutcome {
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
