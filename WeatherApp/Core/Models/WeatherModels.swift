import Foundation

struct WeatherLocation: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
    var isCurrentLocation: Bool

    init(
        id: UUID = UUID(),
        name: String,
        region: String,
        latitude: Double,
        longitude: Double,
        isCurrentLocation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.isCurrentLocation = isCurrentLocation
    }

    var displayName: String {
        region.isEmpty ? name : "\(name), \(region)"
    }
}

enum WeatherCondition: String, Codable, Sendable {
    case clear
    case mostlyClear
    case partlyCloudy
    case cloudy
    case rain
    case heavyRain
    case thunderstorm
    case snow
    case fog
    case windy
    case unknown

    var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .mostlyClear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .snow: "cloud.snow.fill"
        case .fog: "cloud.fog.fill"
        case .windy: "wind"
        case .unknown: "cloud.fill"
        }
    }
}

enum WeatherProvider: String, Codable, Sendable {
    case nwsObservation = "National Weather Service observation"
    case nwsForecast = "National Weather Service forecast"
    case noaaRadar = "NOAA radar"
    case weatherKit = "Apple Weather"
    case mock = "Preview data"
}

struct WeatherSourceMetadata: Hashable, Codable, Sendable {
    var provider: WeatherProvider
    var productName: String
    var sourceName: String?
    var observedAt: Date?
    var issuedAt: Date?
    var validFrom: Date?
    var validTo: Date?
    var fetchedAt: Date
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

struct CurrentConditions: Hashable, Sendable {
    var temperature: Double
    var apparentTemperature: Double?
    var condition: WeatherCondition
    var conditionDescription: String
    var humidity: Double?
    var dewPoint: Double?
    var windSpeed: Double?
    var windGust: Double?
    var windDirection: String?
    var visibilityMiles: Double?
    var pressureMillibars: Double?
    var source: WeatherSourceMetadata
}

struct HourlyForecastItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var date: Date
    var temperature: Double
    var apparentTemperature: Double?
    var condition: WeatherCondition
    var precipitationChance: Double?
    var humidity: Double?
    var dewPoint: Double?
    var windSpeed: Double?
    var windGust: Double?
    var source: WeatherSourceMetadata

    init(
        id: UUID = UUID(),
        date: Date,
        temperature: Double,
        apparentTemperature: Double? = nil,
        condition: WeatherCondition,
        precipitationChance: Double? = nil,
        humidity: Double? = nil,
        dewPoint: Double? = nil,
        windSpeed: Double? = nil,
        windGust: Double? = nil,
        source: WeatherSourceMetadata
    ) {
        self.id = id
        self.date = date
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.condition = condition
        self.precipitationChance = precipitationChance
        self.humidity = humidity
        self.dewPoint = dewPoint
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.source = source
    }
}

struct DailyForecastItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var date: Date
    var daytimeHigh: Double?
    var overnightLow: Double?
    var daytimeCondition: WeatherCondition
    var nighttimeCondition: WeatherCondition?
    var daytimeDescription: String
    var nighttimeDescription: String?
    var daytimePrecipitationChance: Double?
    var nighttimePrecipitationChance: Double?
    var windDescription: String?
    var nighttimeWindDescription: String?
    var source: WeatherSourceMetadata

    init(
        id: UUID = UUID(),
        date: Date,
        daytimeHigh: Double?,
        overnightLow: Double?,
        daytimeCondition: WeatherCondition,
        nighttimeCondition: WeatherCondition? = nil,
        daytimeDescription: String,
        nighttimeDescription: String? = nil,
        daytimePrecipitationChance: Double? = nil,
        nighttimePrecipitationChance: Double? = nil,
        windDescription: String? = nil,
        nighttimeWindDescription: String? = nil,
        source: WeatherSourceMetadata
    ) {
        self.id = id
        self.date = date
        self.daytimeHigh = daytimeHigh
        self.overnightLow = overnightLow
        self.daytimeCondition = daytimeCondition
        self.nighttimeCondition = nighttimeCondition
        self.daytimeDescription = daytimeDescription
        self.nighttimeDescription = nighttimeDescription
        self.daytimePrecipitationChance = daytimePrecipitationChance
        self.nighttimePrecipitationChance = nighttimePrecipitationChance
        self.windDescription = windDescription
        self.nighttimeWindDescription = nighttimeWindDescription
        self.source = source
    }
}

struct MinutePrecipitationSample: Identifiable, Hashable, Sendable {
    let id: UUID
    var date: Date
    var probability: Double
    var intensity: Double?
    var source: WeatherSourceMetadata

    init(
        id: UUID = UUID(),
        date: Date,
        probability: Double,
        intensity: Double? = nil,
        source: WeatherSourceMetadata
    ) {
        self.id = id
        self.date = date
        self.probability = probability
        self.intensity = intensity
        self.source = source
    }
}

enum WeatherAlertSeverity: String, Codable, Sendable {
    case minor
    case moderate
    case severe
    case extreme
    case unknown
}

struct WeatherAlert: Identifiable, Hashable, Sendable {
    let id: String
    var event: String
    var headline: String
    var severity: WeatherAlertSeverity
    var effectiveAt: Date
    var expiresAt: Date?
    var description: String
    var instructions: String?
    var issuingOffice: String?
    var source: WeatherSourceMetadata
}

struct SolarWeather: Hashable, Sendable {
    var sunrise: Date?
    var sunset: Date?
    var uvIndex: Int?
    var source: WeatherSourceMetadata
}

struct WeatherSnapshot: Sendable {
    var location: WeatherLocation
    var current: CurrentConditions
    var hourly: [HourlyForecastItem]
    var daily: [DailyForecastItem]
    var minutePrecipitation: [MinutePrecipitationSample]
    var alerts: [WeatherAlert]
    var solar: SolarWeather?
    var availability: [WeatherProduct: WeatherProductAvailability]
    var fetchedAt: Date

    func availability(for product: WeatherProduct) -> WeatherProductAvailability {
        availability[product] ?? .available
    }
}
