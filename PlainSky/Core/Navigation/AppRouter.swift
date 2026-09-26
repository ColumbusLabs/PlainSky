import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab
    var forecastMode: ForecastMode

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("--weather-tab=forecast") {
            selectedTab = .forecast
        } else if arguments.contains("--weather-tab=radar") {
            selectedTab = .radar
        } else if arguments.contains("--weather-tab=settings")
                    || arguments.contains("--weather-tab=places") {
            selectedTab = .settings
        } else {
            selectedTab = .today
        }

        forecastMode = arguments.contains("--weather-forecast=hourly")
            ? .hourly
            : .daily
    }

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
    case settings
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
