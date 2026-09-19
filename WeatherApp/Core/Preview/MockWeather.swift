import Foundation

enum MockWeather {
    static var snapshot: WeatherSnapshot {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent

        let observationSource = WeatherSourceMetadata(
            provider: .mock,
            productName: "Current observation",
            sourceName: "Indianapolis preview station",
            observedAt: now.addingTimeInterval(-7 * 60),
            issuedAt: nil,
            validFrom: nil,
            validTo: nil,
            fetchedAt: now,
            expiresAt: now.addingTimeInterval(20 * 60)
        )

        let forecastSource = WeatherSourceMetadata(
            provider: .mock,
            productName: "Hourly forecast",
            sourceName: "Preview forecast grid",
            observedAt: nil,
            issuedAt: now.addingTimeInterval(-18 * 60),
            validFrom: now,
            validTo: calendar.date(byAdding: .day, value: 7, to: now),
            fetchedAt: now,
            expiresAt: now.addingTimeInterval(30 * 60)
        )

        let appleSource = WeatherSourceMetadata(
            provider: .mock,
            productName: "Next-hour precipitation",
            sourceName: "Preview minute forecast",
            observedAt: nil,
            issuedAt: now,
            validFrom: now,
            validTo: now.addingTimeInterval(60 * 60),
            fetchedAt: now,
            expiresAt: now.addingTimeInterval(10 * 60)
        )

        let location = WeatherLocation(
            name: "Indianapolis",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581,
            isCurrentLocation: true
        )

        let temperatures = [74, 73, 72, 70, 68, 67, 66, 65, 64, 63, 62, 62, 61, 61, 62, 64, 67, 70, 73, 76, 78, 79, 78, 76]
        let rainChances = [8, 8, 10, 12, 16, 20, 24, 28, 30, 26, 22, 18, 15, 12, 10, 8, 8, 6, 6, 8, 10, 12, 14, 16]

        let hourly = temperatures.enumerated().map { index, temperature in
            HourlyForecastItem(
                date: calendar.date(byAdding: .hour, value: index, to: now) ?? now,
                temperature: Double(temperature),
                apparentTemperature: Double(temperature),
                condition: index < 5 ? .partlyCloudy : (index < 14 ? .mostlyClear : .clear),
                precipitationChance: Double(rainChances[index]) / 100,
                humidity: 0.56 + Double(min(index, 10)) * 0.02,
                dewPoint: 58 + Double(index % 4),
                windSpeed: 7 + Double(index % 4),
                windGust: 13 + Double(index % 5),
                source: forecastSource
            )
        }

        let highs = [79, 82, 77, 73, 76, 80, 81]
        let lows = [61, 64, 59, 55, 57, 60, 62]
        let conditions: [WeatherCondition] = [.partlyCloudy, .clear, .rain, .partlyCloudy, .clear, .clear, .cloudy]
        let rain = [0.12, 0.08, 0.68, 0.22, 0.08, 0.10, 0.31]

        let daily = (0..<7).map { index in
            DailyForecastItem(
                date: calendar.date(byAdding: .day, value: index, to: now) ?? now,
                daytimeHigh: Double(highs[index]),
                overnightLow: Double(lows[index]),
                daytimeCondition: conditions[index],
                daytimeDescription: index == 2 ? "Showers likely, mainly during the afternoon." : "Comfortable with a mix of sun and clouds.",
                nighttimeDescription: index == 2 ? "Showers tapering late." : "Mostly clear overnight.",
                daytimePrecipitationChance: rain[index],
                nighttimePrecipitationChance: max(0.04, rain[index] - 0.08),
                windDescription: "SW 7–12 mph",
                source: forecastSource
            )
        }

        let minutePrecipitation = stride(from: 0, through: 60, by: 5).map { minute in
            let probability: Double
            if minute < 20 {
                probability = 0.06
            } else if minute < 40 {
                probability = Double(minute - 15) / 100
            } else {
                probability = 0.28
            }

            return MinutePrecipitationSample(
                date: now.addingTimeInterval(Double(minute) * 60),
                probability: probability,
                intensity: probability > 0.20 ? 0.12 : 0,
                source: appleSource
            )
        }

        return WeatherSnapshot(
            location: location,
            current: CurrentConditions(
                temperature: 74,
                apparentTemperature: 75,
                condition: .partlyCloudy,
                conditionDescription: "Partly Cloudy",
                humidity: 0.58,
                dewPoint: 59,
                windSpeed: 8,
                windGust: 14,
                windDirection: "SW",
                visibilityMiles: 10,
                pressureMillibars: 1016,
                source: observationSource
            ),
            hourly: hourly,
            daily: daily,
            minutePrecipitation: minutePrecipitation,
            alerts: [],
            solar: SolarWeather(
                sunrise: calendar.date(bySettingHour: 7, minute: 28, second: 0, of: now),
                sunset: calendar.date(bySettingHour: 19, minute: 43, second: 0, of: now),
                uvIndex: 5,
                source: appleSource
            ),
            availability: [
                .currentConditions: .available,
                .hourlyForecast: .available,
                .dailyForecast: .available,
                .alerts: .available,
                .radar: .unavailable("NOAA radar is not connected in preview mode."),
                .minutePrecipitation: .available,
                .uvIndex: .available,
                .solarEvents: .available
            ],
            fetchedAt: now
        )
    }

    static let savedLocations: [WeatherLocation] = [
        WeatherLocation(
            name: "Current Location",
            region: "",
            latitude: 39.7684,
            longitude: -86.1581,
            isCurrentLocation: true
        ),
        WeatherLocation(
            name: "Indianapolis",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581
        ),
        WeatherLocation(
            name: "Pensacola",
            region: "Florida",
            latitude: 30.4213,
            longitude: -87.2169
        )
    ]
}
