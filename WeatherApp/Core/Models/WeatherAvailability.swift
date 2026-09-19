import Foundation

enum WeatherProductAvailability: Equatable, Sendable {
    case available
    case unsupported(String)
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .available:
            nil
        case let .unsupported(message), let .unavailable(message):
            message
        }
    }
}
