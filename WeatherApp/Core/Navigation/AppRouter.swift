import Observation

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var forecastMode: ForecastMode = .daily

    func showHourlyForecast() {
        forecastMode = .hourly
        selectedTab = .forecast
    }

    func showDailyForecast() {
        forecastMode = .daily
        selectedTab = .forecast
    }

    func showRadar() {
        selectedTab = .radar
    }
}

enum AppTab: Hashable {
    case today
    case forecast
    case radar
    case places
}

enum ForecastMode: String, CaseIterable, Identifiable {
    case daily
    case hourly

    var id: Self { self }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .hourly: "Hourly"
        }
    }
}
