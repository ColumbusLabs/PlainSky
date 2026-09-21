import Foundation

struct NWSWeatherProvider: PrimaryWeatherProviding {
    private let client: NWSAPIClient
    private let now: () -> Date

    init(
        client: NWSAPIClient = NWSAPIClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.now = now
    }

    func weather(for location: WeatherLocation) async throws -> PrimaryWeatherPayload {
        let fetchedAt = now()
        let point = try await client.point(for: location)
        let properties = point.properties

        async let forecastResponse = try? client.forecast(url: properties.forecast)
        async let hourlyResponse = try? client.hourlyForecast(url: properties.forecastHourly)
        async let gridResponse = try? client.gridData(url: properties.forecastGridData)
        async let stationCollection = try? client.stations(url: properties.observationStations)
        async let alertCollection = try? client.activeAlerts(for: location)

        let dailyResponse = await forecastResponse
        let hourlyForecastResponse = await hourlyResponse
        let grid = await gridResponse
        let stations = await stationCollection
        let alertsResponse = await alertCollection

        let sourceName = "NWS \(properties.gridId) forecast grid"

        let daily: [DailyForecastItem]
        let dailyAvailability: WeatherProductAvailability

        if let dailyResponse {
            daily = NWSMapper.dailyForecast(
                response: dailyResponse,
                timeZoneIdentifier: properties.timeZone,
                sourceName: sourceName,
                fetchedAt: fetchedAt
            )
            dailyAvailability = daily.isEmpty
                ? .unavailable("NWS returned no usable daily forecast periods.")
                : .available
        } else {
            daily = []
            dailyAvailability = .unavailable("Unable to refresh the NWS daily forecast.")
        }

        let hourly: [HourlyForecastItem]
        let hourlyAvailability: WeatherProductAvailability

        if let hourlyForecastResponse {
            hourly = NWSMapper.hourlyForecast(
                response: hourlyForecastResponse,
                grid: grid?.properties,
                sourceName: sourceName,
                fetchedAt: fetchedAt
            )
            hourlyAvailability = hourly.isEmpty
                ? .unavailable("NWS returned no usable hourly forecast periods.")
                : .available
        } else {
            hourly = []
            hourlyAvailability = .unavailable("Unable to refresh the NWS hourly forecast.")
        }

        let alerts: [WeatherAlert]
        let alertsAvailability: WeatherProductAvailability

        if let alertsResponse {
            alerts = NWSMapper.alerts(
                collection: alertsResponse,
                fetchedAt: fetchedAt
            )
            alertsAvailability = .available
        } else {
            alerts = []
            alertsAvailability = .unavailable(
                "Unable to check National Weather Service alerts."
            )
        }

        let current = await currentConditions(
            stations: stations?.features.map(\.properties) ?? [],
            fetchedAt: fetchedAt
        )

        let currentAvailability: WeatherProductAvailability = current == nil
            ? .unavailable("No fresh usable NWS station observation was available.")
            : .available

        return PrimaryWeatherPayload(
            current: current,
            hourly: hourly,
            daily: daily,
            alerts: alerts,
            availability: [
                .currentConditions: currentAvailability,
                .hourlyForecast: hourlyAvailability,
                .dailyForecast: dailyAvailability,
                .alerts: alertsAvailability
            ]
        )
    }

    private func currentConditions(
        stations: [NWSStationProperties],
        fetchedAt: Date
    ) async -> CurrentConditions? {
        for station in stations.prefix(5) {
            guard let observation = try? await client.latestObservation(
                stationIdentifier: station.stationIdentifier
            ) else {
                continue
            }

            if let current = NWSMapper.currentConditions(
                station: station,
                observation: observation,
                fetchedAt: fetchedAt,
                now: fetchedAt
            ) {
                return current
            }
        }

        return nil
    }
}
