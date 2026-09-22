import Foundation

protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession {
    /// Sized so NWS forecast and grid responses (~150–200 KB) fit and their
    /// Cache-Control lifetimes are honored; the shared session's cache is too small.
    static let weather: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()
}

struct URLSessionHTTPClient: HTTPClient {
    /// NWS documents that rate-limited requests "may be retried after the limit clears
    /// (typically within 5 seconds)"; its CDN answers those with 403.
    static let retryableStatusCodes: Set<Int> = [403, 429, 500, 502, 503, 504]

    private let session: URLSession
    private let retryDelay: Duration

    init(session: URLSession = .weather, retryDelay: Duration = .seconds(5)) {
        self.session = session
        self.retryDelay = retryDelay
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await attempt(request)
        } catch let ProviderError.httpStatus(code) where Self.retryableStatusCodes.contains(code) {
            try await Task.sleep(for: retryDelay)
            return try await attempt(request)
        }
    }

    private func attempt(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.httpStatus(httpResponse.statusCode)
        }

        return (data, httpResponse)
    }
}

enum ProviderError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)
    case missingRequiredData(String)
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The provider URL could not be created."
        case .invalidResponse:
            "The weather provider returned an invalid response."
        case .httpStatus(403), .httpStatus(429):
            "The weather service is limiting requests right now. It will retry shortly."
        case let .httpStatus(code) where code >= 500:
            "The weather service is having trouble right now. It will retry shortly."
        case let .httpStatus(code):
            "The weather service returned an unexpected response (HTTP \(code))."
        case let .decoding(message):
            "The provider response could not be decoded: \(message)"
        case let .missingRequiredData(message):
            "Required provider data is missing: \(message)"
        case let .notConfigured(message):
            message
        }
    }
}
