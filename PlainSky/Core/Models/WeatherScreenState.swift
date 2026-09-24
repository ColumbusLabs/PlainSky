import Foundation

struct WeatherRequestLocationKey: Hashable, Codable, Sendable {
    let id: UUID
    let latitudeBits: UInt64
    let longitudeBits: UInt64

    init(_ location: WeatherLocation) {
        id = location.id
        latitudeBits = location.latitude.bitPattern
        longitudeBits = location.longitude.bitPattern
    }
}

struct WeatherRefreshIdentity: Hashable, Sendable {
    let generation: UUID
    let locationKey: WeatherRequestLocationKey
}

enum WeatherRefreshTrigger: Sendable {
    case startup
    case foreground
    case manual
    case locationChange
    case automatic
}

struct WeatherRequestBudgets: Sendable {
    let current: Duration
    let currentCandidate: Duration
    let routing: Duration
    let stationDirectory: Duration
    let alerts: Duration
    let hourly: Duration
    let daily: Duration
    let grid: Duration
    let weatherKit: Duration
    let radar: Duration

    init(
        current: Duration = .seconds(4),
        currentCandidate: Duration = .seconds(2),
        routing: Duration = .seconds(8),
        stationDirectory: Duration = .seconds(4),
        alerts: Duration = .seconds(6),
        hourly: Duration = .seconds(8),
        daily: Duration = .seconds(8),
        grid: Duration = .seconds(10),
        weatherKit: Duration = .seconds(10),
        radar: Duration = .seconds(10)
    ) {
        self.current = current
        self.currentCandidate = currentCandidate
        self.routing = routing
        self.stationDirectory = stationDirectory
        self.alerts = alerts
        self.hourly = hourly
        self.daily = daily
        self.grid = grid
        self.weatherKit = weatherKit
        self.radar = radar
    }

    static let standard = WeatherRequestBudgets()
}

struct WeatherRefreshContext: Sendable {
    let identity: WeatherRefreshIdentity
    let startedAt: Date
    let monotonicStart: ContinuousClock.Instant
    let trigger: WeatherRefreshTrigger
    let requestBudgets: WeatherRequestBudgets

    init(
        location: WeatherLocation,
        generation: UUID = UUID(),
        now: Date = Date(),
        trigger: WeatherRefreshTrigger = .manual,
        requestBudgets: WeatherRequestBudgets = .standard
    ) {
        identity = WeatherRefreshIdentity(
            generation: generation,
            locationKey: WeatherRequestLocationKey(location)
        )
        startedAt = now
        monotonicStart = ContinuousClock().now
        self.trigger = trigger
        self.requestBudgets = requestBudgets
    }
}

struct WeatherValidationMetadata: Equatable, Sendable {
    let source: WeatherSourceMetadata
    let provider: WeatherProvider
    let validatedAt: Date
    let sourceObservedAt: Date?
    let sourceIssuedAt: Date?
    let validFrom: Date?
    let validTo: Date?
    let expiresAt: Date?
    let sourceRevision: String?

    init(
        source: WeatherSourceMetadata,
        validatedAt: Date? = nil,
        sourceRevision: String? = nil
    ) {
        self.source = source
        provider = source.provider
        self.validatedAt = validatedAt ?? source.validatedAt ?? source.fetchedAt
        sourceObservedAt = source.observedAt
        sourceIssuedAt = source.issuedAt
        validFrom = source.validFrom
        validTo = source.validTo
        expiresAt = source.expiresAt
        self.sourceRevision = sourceRevision
    }

    init(
        provider: WeatherProvider,
        validatedAt: Date,
        sourceObservedAt: Date? = nil,
        sourceIssuedAt: Date? = nil,
        validFrom: Date? = nil,
        validTo: Date? = nil,
        expiresAt: Date? = nil,
        sourceRevision: String? = nil
    ) {
        source = WeatherSourceMetadata(
            provider: provider,
            productName: "Weather product",
            sourceName: nil,
            observedAt: sourceObservedAt,
            issuedAt: sourceIssuedAt,
            validFrom: validFrom,
            validTo: validTo,
            fetchedAt: validatedAt,
            expiresAt: expiresAt,
            validatedAt: validatedAt
        )
        self.provider = provider
        self.validatedAt = validatedAt
        self.sourceObservedAt = sourceObservedAt
        self.sourceIssuedAt = sourceIssuedAt
        self.validFrom = validFrom
        self.validTo = validTo
        self.expiresAt = expiresAt
        self.sourceRevision = sourceRevision
    }
}

enum WeatherProductState<Value: Sendable>: Sendable {
    case loading
    case available(Value, WeatherValidationMetadata)
    case unsupported(String)
    case unavailable(String)

    var value: Value? {
        guard case let .available(value, _) = self else { return nil }
        return value
    }

    var validation: WeatherValidationMetadata? {
        guard case let .available(_, validation) = self else { return nil }
        return validation
    }

    var availability: WeatherProductAvailability {
        switch self {
        case .loading:
            .loading
        case .available:
            .available
        case let .unsupported(message):
            .unsupported(message)
        case let .unavailable(message):
            .unavailable(message)
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .loading, .available:
            nil
        case let .unsupported(message), let .unavailable(message):
            message
        }
    }

    static func available(
        _ value: Value,
        source: WeatherSourceMetadata,
        validatedAt: Date? = nil,
        sourceRevision: String? = nil
    ) -> Self {
        .available(
            value,
            WeatherValidationMetadata(
                source: source,
                validatedAt: validatedAt,
                sourceRevision: sourceRevision
            )
        )
    }
}

struct WeatherScreenState: Sendable {
    var location: WeatherLocation
    var identity: WeatherRefreshIdentity?
    var routeRevision: String?
    var timeZoneIdentifier: String?
    var current: WeatherProductState<CurrentConditions>
    var hourly: WeatherProductState<[HourlyForecastItem]>
    var daily: WeatherProductState<[DailyForecastItem]>
    var alerts: WeatherProductState<[WeatherAlert]>
    var minutePrecipitation: WeatherProductState<[MinutePrecipitationSample]>
    var uvIndex: WeatherProductState<Int>
    var solarEvents: WeatherProductState<SolarWeather>
    var radar: WeatherProductState<Void>

    init(location: WeatherLocation, loading: Bool = true) {
        self.location = location
        identity = nil
        routeRevision = nil
        timeZoneIdentifier = nil
        current = .loading
        hourly = .loading
        daily = .loading
        alerts = .loading
        minutePrecipitation = .loading
        uvIndex = .loading
        solarEvents = .loading
        radar = .loading

        if !loading {
            current = .unavailable("Weather has not been checked yet.")
            hourly = .unavailable("Weather has not been checked yet.")
            daily = .unavailable("Weather has not been checked yet.")
            alerts = .unavailable("Alert status has not been checked yet.")
            minutePrecipitation = .unavailable("Weather has not been checked yet.")
            uvIndex = .unavailable("Weather has not been checked yet.")
            solarEvents = .unavailable("Weather has not been checked yet.")
            radar = .unavailable("Radar has not been checked yet.")
        }
    }

    init(preview snapshot: WeatherSnapshot) {
        let date = snapshot.fetchedAt
        location = snapshot.location
        identity = nil
        routeRevision = nil
        timeZoneIdentifier = nil

        current = .available(
            snapshot.current,
            WeatherValidationMetadata(source: snapshot.current.source, validatedAt: date)
        )
        hourly = Self.state(
            snapshot.hourly,
            availability: snapshot.availability(for: .hourlyForecast),
            source: snapshot.hourly.first?.source,
            fallbackProvider: .nwsForecast,
            fallbackName: "Hourly forecast",
            at: date
        )
        daily = Self.state(
            snapshot.daily,
            availability: snapshot.availability(for: .dailyForecast),
            source: snapshot.daily.first?.source,
            fallbackProvider: .nwsForecast,
            fallbackName: "Daily forecast",
            at: date
        )
        alerts = Self.state(
            snapshot.alerts,
            availability: snapshot.availability(for: .alerts),
            source: snapshot.alerts.first?.source,
            fallbackProvider: .nwsForecast,
            fallbackName: "NWS alerts",
            at: date
        )
        minutePrecipitation = Self.state(
            snapshot.minutePrecipitation,
            availability: snapshot.availability(for: .minutePrecipitation),
            source: snapshot.minutePrecipitation.first?.source,
            fallbackProvider: .weatherKit,
            fallbackName: "Next-hour precipitation",
            at: date
        )

        if let solar = snapshot.solar {
            let metadata = WeatherValidationMetadata(source: solar.source, validatedAt: date)
            uvIndex = solar.uvIndex.map { .available($0, metadata) }
                ?? .unsupported("UV data is not available for this location.")
            solarEvents = solar.sunrise != nil || solar.sunset != nil
                ? .available(solar, metadata)
                : .unsupported("Sunrise and sunset are not available for this location.")
        } else {
            uvIndex = Self.availabilityState(snapshot.availability(for: .uvIndex))
            solarEvents = Self.availabilityState(snapshot.availability(for: .solarEvents))
        }

        switch snapshot.availability(for: .radar) {
        case .available:
            radar = .available(
                (),
                WeatherValidationMetadata(
                    provider: .noaaRadar,
                    validatedAt: date
                )
            )
        case let .unsupported(message):
            radar = .unsupported(message)
        case let .unavailable(message):
            radar = .unavailable(message)
        case .loading:
            radar = .loading
        }
    }

    mutating func beginRefresh(_ context: WeatherRefreshContext) {
        identity = context.identity
        location = WeatherScreenState.replacingCoordinates(in: location, from: context.identity.locationKey)
        routeRevision = nil
        timeZoneIdentifier = nil
        current = .loading
        hourly = .loading
        daily = .loading
        alerts = .loading
        minutePrecipitation = .loading
        uvIndex = .loading
        solarEvents = .loading
        radar = .loading
    }

    mutating func clearWeather(generation: UUID? = nil) {
        identity = nil
        routeRevision = nil
        timeZoneIdentifier = nil
        current = .loading
        hourly = .loading
        daily = .loading
        alerts = .loading
        minutePrecipitation = .loading
        uvIndex = .loading
        solarEvents = .loading
        radar = .loading
        if let generation {
            identity = WeatherRefreshIdentity(
                generation: generation,
                locationKey: WeatherRequestLocationKey(location)
            )
        }
    }

    private static func state<Value: Sendable>(
        _ value: Value,
        availability: WeatherProductAvailability,
        source: WeatherSourceMetadata?,
        fallbackProvider: WeatherProvider,
        fallbackName: String,
        at date: Date
    ) -> WeatherProductState<Value> {
        switch availability {
        case .available:
            let metadata = source ?? WeatherSourceMetadata(
                provider: fallbackProvider,
                productName: fallbackName,
                sourceName: nil,
                observedAt: nil,
                issuedAt: nil,
                validFrom: nil,
                validTo: nil,
                fetchedAt: date,
                expiresAt: nil,
                validatedAt: date
            )
            return .available(
                value,
                WeatherValidationMetadata(source: metadata, validatedAt: date)
            )
        case let .unsupported(message):
            return .unsupported(message)
        case let .unavailable(message):
            return .unavailable(message)
        case .loading:
            return .loading
        }
    }

    private static func availabilityState<Value: Sendable>(
        _ availability: WeatherProductAvailability
    ) -> WeatherProductState<Value> {
        switch availability {
        case .loading:
            .loading
        case .available:
            .unavailable("The provider returned no usable value.")
        case let .unsupported(message):
            .unsupported(message)
        case let .unavailable(message):
            .unavailable(message)
        }
    }

    private static func replacingCoordinates(
        in location: WeatherLocation,
        from key: WeatherRequestLocationKey
    ) -> WeatherLocation {
        var location = location
        location = WeatherLocation(
            id: key.id,
            name: location.name,
            region: location.region,
            latitude: Double(bitPattern: key.latitudeBits),
            longitude: Double(bitPattern: key.longitudeBits),
            isCurrentLocation: location.isCurrentLocation
        )
        return location
    }
}

extension WeatherScreenState {
    func availability(for product: WeatherProduct) -> WeatherProductAvailability {
        switch product {
        case .currentConditions: current.availability
        case .hourlyForecast: hourly.availability
        case .dailyForecast: daily.availability
        case .alerts: alerts.availability
        case .radar: radar.availability
        case .minutePrecipitation: minutePrecipitation.availability
        case .uvIndex: uvIndex.availability
        case .solarEvents: solarEvents.availability
        }
    }
}

enum WeatherProductEvent: Sendable {
    case routeRevision(String, timeZoneIdentifier: String?)
    case current(WeatherProductState<CurrentConditions>)
    case hourly(WeatherProductState<[HourlyForecastItem]>)
    case daily(WeatherProductState<[DailyForecastItem]>)
    case alerts(WeatherProductState<[WeatherAlert]>)
    case minutePrecipitation(WeatherProductState<[MinutePrecipitationSample]>)
    case uvIndex(WeatherProductState<Int>)
    case solarEvents(WeatherProductState<SolarWeather>)
    case radar(WeatherProductState<Void>)
    case terminal
}

struct WeatherProductUpdate: Sendable {
    let identity: WeatherRefreshIdentity
    let sourceRevision: String?
    let event: WeatherProductEvent

    init(
        identity: WeatherRefreshIdentity,
        sourceRevision: String? = nil,
        event: WeatherProductEvent
    ) {
        self.identity = identity
        self.sourceRevision = sourceRevision
        self.event = event
    }
}

typealias WeatherProductUpdateHandler = @MainActor @Sendable (WeatherProductUpdate) async -> Void
