import Foundation

protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        case let .httpStatus(code):
            "The weather provider returned HTTP \(code)."
        case let .decoding(message):
            "The provider response could not be decoded: \(message)"
        case let .missingRequiredData(message):
            "Required provider data is missing: \(message)"
        case let .notConfigured(message):
            message
        }
    }
}
