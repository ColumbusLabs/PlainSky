import Foundation

struct NWSFeatureCollection<Properties: Decodable>: Decodable {
    let features: [NWSFeature<Properties>]
}

struct NWSFeature<Properties: Decodable>: Decodable {
    let properties: Properties
}

struct NWSPointResponse: Decodable {
    let properties: NWSPointProperties
}

struct NWSPointProperties: Decodable {
    let gridId: String
    let gridX: Int
    let gridY: Int
    let forecast: URL
    let forecastHourly: URL
    let forecastGridData: URL
    let observationStations: URL
}

struct NWSForecastResponse: Decodable {
    let properties: NWSForecastProperties
}

struct NWSForecastProperties: Decodable {
    let updated: String?
    let generatedAt: String?
    let periods: [NWSForecastPeriod]
}

struct NWSForecastPeriod: Decodable {
    let number: Int
    let name: String
    let startTime: String
    let endTime: String
    let isDaytime: Bool
    let temperature: Double
    let temperatureUnit: String
    let probabilityOfPrecipitation: NWSQuantitativeValue?
    let windSpeed: String
    let windDirection: String
    let shortForecast: String
    let detailedForecast: String
}

struct NWSStationProperties: Decodable {
    let stationIdentifier: String
    let name: String
}

struct NWSObservationResponse: Decodable {
    let properties: NWSObservationProperties
}

struct NWSObservationProperties: Decodable {
    let timestamp: String
    let textDescription: String?
    let temperature: NWSQuantitativeValue?
    let dewpoint: NWSQuantitativeValue?
    let windDirection: NWSQuantitativeValue?
    let windSpeed: NWSQuantitativeValue?
    let windGust: NWSQuantitativeValue?
    let barometricPressure: NWSQuantitativeValue?
    let visibility: NWSQuantitativeValue?
    let relativeHumidity: NWSQuantitativeValue?
    let windChill: NWSQuantitativeValue?
    let heatIndex: NWSQuantitativeValue?
}

struct NWSQuantitativeValue: Decodable {
    let unitCode: String?
    let value: Double?
}

struct NWSAlertCollection: Decodable {
    let features: [NWSAlertFeature]
}

struct NWSAlertFeature: Decodable {
    let id: String
    let properties: NWSAlertProperties
}

struct NWSAlertProperties: Decodable {
    let event: String
    let headline: String?
    let description: String
    let instruction: String?
    let severity: String?
    let effective: String
    let expires: String?
    let senderName: String?
}
