import Foundation

enum WeatherProductAvailability: Codable, Equatable, Sendable {
    case loading
    case available
    case unsupported(String)
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
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
}
