import Foundation

enum NWSMapper {
    static let observationMaxAge: TimeInterval = 90 * 60

    static func currentConditions(
        station: NWSStationProperties,
        observation: NWSObservationResponse,
        fetchedAt: Date,
        now: Date = Date(),
        maxAge: TimeInterval = observationMaxAge
    ) -> CurrentConditions? {
        guard let observedAt = NWSParsing.date(observation.properties.timestamp) else {
            return nil
        }

        let age = now.timeIntervalSince(observedAt)
        guard age >= -10 * 60, age <= maxAge else {
            return nil
        }

        guard let temperature = NWSUnitConverter.temperatureFahrenheit(
            observation.properties.temperature
        ) else {
            return nil
        }

        let apparentTemperature =
            NWSUnitConverter.temperatureFahrenheit(observation.properties.heatIndex)
            ?? NWSUnitConverter.temperatureFahrenheit(observation.properties.windChill)

        let description = nonEmpty(observation.properties.textDescription)
            ?? "Observed conditions"

        return CurrentConditions(
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            condition: NWSConditionMapper.condition(from: description),
            conditionDescription: description,
            humidity: NWSUnitConverter.humidityFraction(
                observation.properties.relativeHumidity
            ),
            dewPoint: NWSUnitConverter.temperatureFahrenheit(
                observation.properties.dewpoint
            ),
            windSpeed: NWSUnitConverter.speedMPH(
                observation.properties.windSpeed
            ),
            windGust: NWSUnitConverter.speedMPH(
                observation.properties.windGust
            ),
            windDirection: NWSUnitConverter.compassDirection(
                observation.properties.windDirection
            ),
            visibilityMiles: NWSUnitConverter.visibilityMiles(
                observation.properties.visibility
            ),
            pressureMillibars: NWSUnitConverter.pressureMillibars(
                observation.properties.barometricPressure
            ),
            source: WeatherSourceMetadata(
                provider: .nwsObservation,
                productName: "Current observation",
                sourceName: "\(station.name) (\(station.stationIdentifier))",
                observedAt: observedAt,
                issuedAt: nil,
                validFrom: nil,
                validTo: nil,
                fetchedAt: fetchedAt,
                expiresAt: observedAt.addingTimeInterval(maxAge)
            )
        )
    }

    static func hourlyForecast(
        response: NWSForecastResponse,
        grid: NWSGridpointProperties?,
        sourceName: String,
        fetchedAt: Date
    ) -> [HourlyForecastItem] {
        let issuedAt = forecastIssueDate(response.properties)

        return response.properties.periods.compactMap { period in
            guard let start = NWSParsing.date(period.startTime),
                  let end = NWSParsing.date(period.endTime),
                  let temperature = NWSUnitConverter.forecastTemperatureFahrenheit(
                    period.temperature,
                    legacyUnit: period.temperatureUnit
                  ) else {
                return nil
            }

            let apparentTemperature = gridValue(
                grid?.apparentTemperature,
                at: start,
                transform: NWSUnitConverter.temperatureFahrenheit
            )

            let gridHumidity = grid?.relativeHumidity?.value(at: start).map {
                max(0, min(1, $0 / 100))
            }

            let gridDewPoint = gridValue(
                grid?.dewpoint,
                at: start,
                transform: NWSUnitConverter.temperatureFahrenheit
            )

            let gridWindSpeed = gridValue(
                grid?.windSpeed,
                at: start,
                transform: NWSUnitConverter.speedMPH
            )

            let gridWindGust = gridValue(
                grid?.windGust,
                at: start,
                transform: NWSUnitConverter.speedMPH
            )

            let description = nonEmpty(period.shortForecast) ?? "Forecast"

            return HourlyForecastItem(
                date: start,
                temperature: temperature,
                apparentTemperature: apparentTemperature,
                condition: NWSConditionMapper.condition(from: description),
                precipitationChance: NWSUnitConverter.precipitationFraction(
                    period.probabilityOfPrecipitation
                ),
                humidity: NWSUnitConverter.humidityFraction(period.relativeHumidity)
                    ?? gridHumidity,
                dewPoint: NWSUnitConverter.temperatureFahrenheit(period.dewpoint)
                    ?? gridDewPoint,
                windSpeed: NWSUnitConverter.forecastSpeedMPH(period.windSpeed)
                    ?? gridWindSpeed,
                windGust: NWSUnitConverter.forecastSpeedMPH(period.windGust)
                    ?? gridWindGust,
                source: WeatherSourceMetadata(
                    provider: .nwsForecast,
                    productName: "Hourly forecast",
                    sourceName: sourceName,
                    observedAt: nil,
                    issuedAt: issuedAt,
                    validFrom: start,
                    validTo: end,
                    fetchedAt: fetchedAt,
                    expiresAt: end
                )
            )
        }
    }

    static func dailyForecast(
        response: NWSForecastResponse,
        timeZoneIdentifier: String?,
        sourceName: String,
        fetchedAt: Date
    ) -> [DailyForecastItem] {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }

        var buckets: [Date: DayBucket] = [:]

        for period in response.properties.periods {
            guard let start = NWSParsing.date(period.startTime) else { continue }

            let day = calendar.startOfDay(for: start)
            var bucket = buckets[day] ?? DayBucket()

            if period.isDaytime {
                bucket.daytime = period
            } else {
                bucket.nighttime = period
            }

            buckets[day] = bucket
        }

        let issuedAt = forecastIssueDate(response.properties)

        return buckets.keys.sorted().prefix(7).compactMap { date in
            guard let bucket = buckets[date],
                  bucket.daytime != nil || bucket.nighttime != nil else {
                return nil
            }

            let representative = bucket.daytime ?? bucket.nighttime
            guard let representative else { return nil }

            let validFrom = [bucket.daytime, bucket.nighttime]
                .compactMap { $0 }
                .compactMap { NWSParsing.date($0.startTime) }
                .min()

            let validTo = [bucket.daytime, bucket.nighttime]
                .compactMap { $0 }
                .compactMap { NWSParsing.date($0.endTime) }
                .max()

            return DailyForecastItem(
                date: date,
                daytimeHigh: bucket.daytime.flatMap {
                    NWSUnitConverter.forecastTemperatureFahrenheit(
                        $0.temperature,
                        legacyUnit: $0.temperatureUnit
                    )
                },
                overnightLow: bucket.nighttime.flatMap {
                    NWSUnitConverter.forecastTemperatureFahrenheit(
                        $0.temperature,
                        legacyUnit: $0.temperatureUnit
                    )
                },
                daytimeCondition: NWSConditionMapper.condition(
                    from: representative.shortForecast
                ),
                nighttimeCondition: bucket.nighttime.map {
                    NWSConditionMapper.condition(from: $0.shortForecast)
                },
                daytimeDescription: periodDescription(bucket.daytime ?? bucket.nighttime),
                nighttimeDescription: bucket.nighttime.map(periodDescription),
                daytimePrecipitationChance: bucket.daytime.flatMap {
                    NWSUnitConverter.precipitationFraction(
                        $0.probabilityOfPrecipitation
                    )
                },
                nighttimePrecipitationChance: bucket.nighttime.flatMap {
                    NWSUnitConverter.precipitationFraction(
                        $0.probabilityOfPrecipitation
                    )
                },
                windDescription: windDescription(bucket.daytime ?? bucket.nighttime),
                nighttimeWindDescription: windDescription(bucket.nighttime),
                source: WeatherSourceMetadata(
                    provider: .nwsForecast,
                    productName: "Daily forecast",
                    sourceName: sourceName,
                    observedAt: nil,
                    issuedAt: issuedAt,
                    validFrom: validFrom,
                    validTo: validTo,
                    fetchedAt: fetchedAt,
                    expiresAt: validTo
                )
            )
        }
    }

    static func alerts(
        collection: NWSAlertCollection,
        fetchedAt: Date
    ) -> [WeatherAlert] {
        collection.features.compactMap { feature in
            guard let effectiveAt = NWSParsing.date(feature.properties.effective) else {
                return nil
            }

            let expiresAt = NWSParsing.date(feature.properties.expires)

            return WeatherAlert(
                id: feature.id,
                event: feature.properties.event,
                headline: nonEmpty(feature.properties.headline)
                    ?? feature.properties.event,
                severity: alertSeverity(feature.properties.severity),
                effectiveAt: effectiveAt,
                expiresAt: expiresAt,
                description: feature.properties.description,
                instructions: nonEmpty(feature.properties.instruction),
                issuingOffice: nonEmpty(feature.properties.senderName),
                source: WeatherSourceMetadata(
                    provider: .nwsForecast,
                    productName: "Official weather alert",
                    sourceName: nonEmpty(feature.properties.senderName)
                        ?? "National Weather Service",
                    observedAt: nil,
                    issuedAt: NWSParsing.date(feature.properties.sent),
                    validFrom: effectiveAt,
                    validTo: expiresAt,
                    fetchedAt: fetchedAt,
                    expiresAt: expiresAt
                )
            )
        }
        .sorted { lhs, rhs in
            let leftRank = severityRank(lhs.severity)
            let rightRank = severityRank(rhs.severity)

            if leftRank != rightRank {
                return leftRank > rightRank
            }

            return lhs.effectiveAt < rhs.effectiveAt
        }
    }

    static func windDescription(_ period: NWSForecastPeriod?) -> String? {
        guard let period,
              let measurement = period.windSpeed else {
            return nil
        }

        let speedText: String?

        switch measurement {
        case let .text(text):
            speedText = nonEmpty(text)

        case let .quantity(quantity):
            speedText = NWSUnitConverter.speedMPH(quantity).map {
                "\(Int($0.rounded())) mph"
            }

        case let .number(value):
            speedText = "\(Int(value.rounded())) mph"
        }

        guard let speedText else { return nil }

        if let direction = nonEmpty(period.windDirection) {
            return "\(direction) \(speedText)"
        }

        return speedText
    }

    private static func forecastIssueDate(
        _ properties: NWSForecastProperties
    ) -> Date? {
        NWSParsing.date(properties.generatedAt)
            ?? NWSParsing.date(properties.updateTime)
            ?? NWSParsing.date(properties.updated)
    }

    private static func gridValue(
        _ series: NWSGridValueSeries?,
        at date: Date,
        transform: (Double, String?) -> Double?
    ) -> Double? {
        guard let series,
              let value = series.value(at: date) else {
            return nil
        }

        return transform(value, series.uom)
    }

    private static func periodDescription(
        _ period: NWSForecastPeriod?
    ) -> String {
        guard let period else { return "" }

        return nonEmpty(period.detailedForecast)
            ?? nonEmpty(period.shortForecast)
            ?? ""
    }

    private static func alertSeverity(
        _ value: String?
    ) -> WeatherAlertSeverity {
        switch value?.lowercased() {
        case "minor":
            .minor
        case "moderate":
            .moderate
        case "severe":
            .severe
        case "extreme":
            .extreme
        default:
            .unknown
        }
    }

    private static func severityRank(
        _ severity: WeatherAlertSeverity
    ) -> Int {
        switch severity {
        case .extreme: 4
        case .severe: 3
        case .moderate: 2
        case .minor: 1
        case .unknown: 0
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct DayBucket {
        var daytime: NWSForecastPeriod?
        var nighttime: NWSForecastPeriod?
    }
}
