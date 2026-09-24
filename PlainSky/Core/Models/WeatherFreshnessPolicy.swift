import Foundation

struct WeatherFreshnessPolicy {
    typealias Clock = () -> Date

    /// Which rules a freshness check applies.
    enum Scope {
        /// Source validity plus the per-product cap on how long a validated
        /// value may be reused without a new check. Used when deciding whether
        /// to refresh and when the app returns from a brief interruption.
        case reuse
        /// Source validity only (observation age, issue age, expiry, local
        /// date). Used to age values out while the app stays in the foreground
        /// so a value disappears when its source stops being valid, not merely
        /// because it was fetched a minute ago.
        case display
    }

    private let clock: Clock
    let longResumeThreshold: TimeInterval

    init(
        longResumeThreshold: TimeInterval = 5 * 60,
        now: @escaping Clock = Date.init
    ) {
        self.longResumeThreshold = longResumeThreshold
        clock = now
    }

    func now() -> Date { clock() }

    func isLongResume(since inactiveAt: Date, now: Date? = nil) -> Bool {
        resolvedNow(now).timeIntervalSince(inactiveAt) >= longResumeThreshold
    }

    func isFresh(
        _ metadata: WeatherValidationMetadata,
        for product: WeatherProduct,
        now: Date? = nil,
        timeZoneIdentifier: String? = nil,
        scope: Scope = .reuse
    ) -> Bool {
        let now = resolvedNow(now)
        let validationAge = now.timeIntervalSince(metadata.validatedAt)
        let withinReuseCap = scope == .display
            || validationAge <= maximumValidationAge(for: product)

        guard validationAge >= -10 * 60,
              withinReuseCap,
              metadata.expiresAt.map({ $0 > now }) ?? true else {
            return false
        }

        switch product {
        case .currentConditions:
            let sourceDate: Date
            let maximumSourceAge: TimeInterval
            switch metadata.provider {
            case .nwsObservation:
                guard let observedAt = metadata.sourceObservedAt else { return false }
                sourceDate = observedAt
                maximumSourceAge = 90 * 60
            case .weatherKit:
                guard let weatherKitDate = metadata.sourceObservedAt ?? metadata.sourceIssuedAt else {
                    return false
                }
                sourceDate = weatherKitDate
                maximumSourceAge = 15 * 60
            case .nwsForecast, .noaaRadar, .mock:
                return false
            }
            let sourceAge = now.timeIntervalSince(sourceDate)
            return sourceAge >= -10 * 60 && sourceAge <= maximumSourceAge

        case .hourlyForecast, .dailyForecast:
            guard metadata.provider == .nwsForecast,
                  let issuedAt = metadata.sourceIssuedAt else {
                return false
            }
            let issueAge = now.timeIntervalSince(issuedAt)
            return issueAge >= -10 * 60 && issueAge <= 12 * 60 * 60

        case .alerts:
            return metadata.provider == .nwsForecast

        case .minutePrecipitation:
            guard metadata.provider == .weatherKit,
                  let validTo = metadata.validTo else {
                return false
            }
            return validTo > now

        case .uvIndex:
            return metadata.provider == .weatherKit

        case .solarEvents:
            guard metadata.provider == .weatherKit,
                  let validFrom = metadata.validFrom else {
                return false
            }
            var calendar = Calendar(identifier: .gregorian)
            if let timeZoneIdentifier,
               let timeZone = TimeZone(identifier: timeZoneIdentifier) {
                calendar.timeZone = timeZone
            }
            return calendar.isDate(validFrom, inSameDayAs: now)

        case .radar:
            return metadata.provider == .noaaRadar
        }
    }

    func refreshedState<Value: Sendable>(
        _ state: WeatherProductState<Value>,
        for product: WeatherProduct,
        now: Date? = nil,
        timeZoneIdentifier: String? = nil,
        scope: Scope = .reuse
    ) -> WeatherProductState<Value> {
        guard case let .available(_, metadata) = state else { return state }
        guard isFresh(
            metadata,
            for: product,
            now: now,
            timeZoneIdentifier: timeZoneIdentifier,
            scope: scope
        ) else {
            return .unavailable("This weather data is no longer fresh. Refresh to check again.")
        }
        return state
    }

    func maximumValidationAge(for product: WeatherProduct) -> TimeInterval {
        switch product {
        case .currentConditions, .uvIndex:
            5 * 60
        case .hourlyForecast, .dailyForecast:
            15 * 60
        case .alerts:
            60
        case .minutePrecipitation:
            2 * 60
        case .solarEvents:
            5 * 60
        case .radar:
            5 * 60
        }
    }

    private func resolvedNow(_ now: Date?) -> Date {
        now ?? clock()
    }
}
