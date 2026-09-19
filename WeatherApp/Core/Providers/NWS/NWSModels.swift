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
    let timeZone: String?
}

struct NWSForecastResponse: Decodable {
    let properties: NWSForecastProperties
}

struct NWSForecastProperties: Decodable {
    let updated: String?
    let generatedAt: String?
    let updateTime: String?
    let periods: [NWSForecastPeriod]
}

struct NWSForecastPeriod: Decodable {
    let number: Int
    let name: String
    let startTime: String
    let endTime: String
    let isDaytime: Bool
    let temperature: NWSForecastMeasurement?
    let temperatureUnit: String?
    let probabilityOfPrecipitation: NWSQuantitativeValue?
    let dewpoint: NWSQuantitativeValue?
    let relativeHumidity: NWSQuantitativeValue?
    let windSpeed: NWSForecastMeasurement?
    let windGust: NWSForecastMeasurement?
    let windDirection: String?
    let shortForecast: String?
    let detailedForecast: String?
}

enum NWSForecastMeasurement: Decodable {
    case quantity(NWSQuantitativeValue)
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let quantity = try? container.decode(NWSQuantitativeValue.self) {
            self = .quantity(quantity)
            return
        }
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        throw DecodingError.typeMismatch(
            NWSForecastMeasurement.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported NWS forecast measurement."
            )
        )
    }
}

struct NWSGridpointResponse: Decodable {
    let properties: NWSGridpointProperties
}

struct NWSGridpointProperties: Decodable {
    let updateTime: String?
    let validTimes: String?
    let apparentTemperature: NWSGridValueSeries?
    let windGust: NWSGridValueSeries?
    let relativeHumidity: NWSGridValueSeries?
    let dewpoint: NWSGridValueSeries?
}

struct NWSGridValueSeries: Decodable {
    let uom: String?
    let values: [NWSGridValue]
}

struct NWSGridValue: Decodable {
    let validTime: String
    let value: Double?
}

struct NWSStationProperties: Decodable {
    let stationIdentifier: String
    let name: String
}

struct NWSObservationResponse: Decodable {
    let properties: NWSObservationProperties
}

struct NWSObservationProperties: Decodable {
    let stationId: String?
    let stationName: String?
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
    let sent: String?
    let effective: String
    let expires: String?
    let senderName: String?
}
