import Foundation
import os

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)

    func data(
        for request: URLRequest,
        context: HTTPRequestContext
    ) async throws -> (Data, HTTPURLResponse)
}

extension HTTPClient {
    func data(
        for request: URLRequest,
        context: HTTPRequestContext
    ) async throws -> (Data, HTTPURLResponse) {
        try await data(for: request)
    }
}

struct HTTPRequestContext: Sendable {
    enum Product: Sendable {
        case routingMetadata
        case stationDirectory
        case currentConditions
        case hourlyForecast
        case dailyForecast
        case alerts
        case gridEnrichment
        case weatherKitSupplement
        case radar

        var signpostName: StaticString {
            switch self {
            case .routingMetadata: "NWS routing"
            case .stationDirectory: "NWS station directory"
            case .currentConditions: "NWS current"
            case .hourlyForecast: "NWS hourly"
            case .dailyForecast: "NWS daily"
            case .alerts: "NWS alerts"
            case .gridEnrichment: "NWS grid enrichment"
            case .weatherKitSupplement: "WeatherKit supplement"
            case .radar: "NOAA radar"
            }
        }
    }

    enum RetryPolicy: Sendable {
        case none
        case bounded(maximumRetries: Int, minimumAttemptBudget: Duration)
    }

    let product: Product
    let identity: WeatherRefreshIdentity
    let deadline: ContinuousClock.Instant
    let retryPolicy: RetryPolicy
    let requiresRevalidation: Bool

    init(
        product: Product,
        identity: WeatherRefreshIdentity,
        deadline: ContinuousClock.Instant,
        retryPolicy: RetryPolicy = .bounded(
            maximumRetries: 1,
            minimumAttemptBudget: .seconds(1)
        ),
        requiresRevalidation: Bool = true
    ) {
        self.product = product
        self.identity = identity
        self.deadline = deadline
        self.retryPolicy = retryPolicy
        self.requiresRevalidation = requiresRevalidation
    }
}

extension WeatherRefreshContext {
    func requestContext(
        for product: HTTPRequestContext.Product,
        retryPolicy: HTTPRequestContext.RetryPolicy = .bounded(
            maximumRetries: 1,
            minimumAttemptBudget: .seconds(1)
        ),
        requiresRevalidation: Bool = true
    ) -> HTTPRequestContext {
        let budget: Duration
        switch product {
        case .currentConditions:
            budget = requestBudgets.current
        case .stationDirectory:
            budget = requestBudgets.stationDirectory
        case .alerts:
            budget = requestBudgets.alerts
        case .hourlyForecast:
            budget = requestBudgets.hourly
        case .dailyForecast:
            budget = requestBudgets.daily
        case .routingMetadata:
            budget = requestBudgets.routing
        case .gridEnrichment:
            budget = requestBudgets.grid
        case .weatherKitSupplement:
            budget = requestBudgets.weatherKit
        case .radar:
            budget = requestBudgets.radar
        }
        return HTTPRequestContext(
            product: product,
            identity: identity,
            deadline: monotonicStart.advanced(by: budget),
            retryPolicy: retryPolicy,
            requiresRevalidation: requiresRevalidation
        )
    }
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

struct URLSessionHTTPClient: HTTPClient, Sendable {
    /// NWS documents that rate-limited requests "may be retried after the limit clears
    /// (typically within 5 seconds)"; its CDN answers those with 403.
    static let retryableStatusCodes: Set<Int> = [403, 429, 500, 502, 503, 504]

    private let session: URLSession
    private let retryDelay: Duration
    private let clock = ContinuousClock()

    init(session: URLSession = .weather, retryDelay: Duration = .seconds(5)) {
        self.session = session
        self.retryDelay = retryDelay
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await attempt(request, context: nil, attemptNumber: 1)
        } catch let failure as HTTPStatusFailure {
            throw ProviderError.httpStatus(failure.statusCode)
        }
    }

    func data(
        for request: URLRequest,
        context: HTTPRequestContext
    ) async throws -> (Data, HTTPURLResponse) {
        let maximumRetries: Int
        let minimumAttemptBudget: Duration
        switch context.retryPolicy {
        case .none:
            maximumRetries = 0
            minimumAttemptBudget = .zero
        case let .bounded(retries, minimumBudget):
            maximumRetries = max(0, retries)
            minimumAttemptBudget = minimumBudget
        }

        var retries = 0
        while true {
            do {
                return try await attempt(
                    request,
                    context: context,
                    attemptNumber: retries + 1
                )
            } catch let failure as HTTPStatusFailure {
                guard retries < maximumRetries,
                      Self.retryableStatusCodes.contains(failure.statusCode) else {
                    throw ProviderError.httpStatus(failure.statusCode)
                }

                let delay = failure.retryAfter ?? retryDelay
                let remaining = clock.now.duration(to: context.deadline)
                guard remaining > delay + minimumAttemptBudget else {
                    throw ProviderError.httpStatus(failure.statusCode)
                }

                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                retries += 1
            }
        }
    }

    private func attempt(
        _ request: URLRequest,
        context: HTTPRequestContext?,
        attemptNumber: Int
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let context {
            let remaining = clock.now.duration(to: context.deadline)
            guard remaining > .zero else { throw ProviderError.deadlineExceeded }
            request.timeoutInterval = min(request.timeoutInterval, remaining.timeInterval)
        }

        let signposter = OSSignposter(subsystem: "com.columbuslabs.plainsky", category: "weather.network")
        let signpostID = signposter.makeSignpostID()
        let productName = context?.product.signpostName ?? "Unclassified weather request"
        let interval = signposter.beginInterval(productName, id: signpostID)
        defer { signposter.endInterval(productName, interval) }

        let metricsDelegate = URLSessionMetricsSignpostDelegate(
            signposter: signposter,
            signpostID: signpostID,
            productName: productName,
            attemptNumber: attemptNumber
        )
        let session = self.session
        let (data, response) = try await Self.withDeadline(context?.deadline) {
            try await session.data(for: request, delegate: metricsDelegate)
        }

        if let context, clock.now >= context.deadline {
            throw ProviderError.deadlineExceeded
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            signposter.emitEvent(
                "HTTP failure",
                id: signpostID,
                "status=\(httpResponse.statusCode) attempt=\(attemptNumber)"
            )
            throw HTTPStatusFailure(
                statusCode: httpResponse.statusCode,
                retryAfter: Self.retryAfter(from: httpResponse)
            )
        }

        signposter.emitEvent(
            "HTTP response",
            id: signpostID,
            "status=\(httpResponse.statusCode) bytes=\(data.count)"
        )
        return (data, httpResponse)
    }

    /// `URLRequest.timeoutInterval` only bounds idle time between packets, so a
    /// slow transfer could outlive its product budget. Racing the request
    /// against the deadline cancels the underlying URLSession task on expiry.
    private static func withDeadline<Value: Sendable>(
        _ deadline: ContinuousClock.Instant?,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        guard let deadline else { return try await operation() }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await ContinuousClock().sleep(until: deadline)
                throw ProviderError.deadlineExceeded
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw ProviderError.deadlineExceeded
            }
            return value
        }
    }

    private static func retryAfter(from response: HTTPURLResponse) -> Duration? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else { return nil }

        if let seconds = TimeInterval(value), seconds >= 0 {
            return .seconds(seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        let seconds = date.timeIntervalSinceNow
        return seconds > 0 ? .seconds(seconds) : .zero
    }
}

private final class URLSessionMetricsSignpostDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let signposter: OSSignposter
    private let signpostID: OSSignpostID
    private let productName: StaticString
    private let attemptNumber: Int

    init(
        signposter: OSSignposter,
        signpostID: OSSignpostID,
        productName: StaticString,
        attemptNumber: Int
    ) {
        self.signposter = signposter
        self.signpostID = signpostID
        self.productName = productName
        self.attemptNumber = attemptNumber
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let transactions = metrics.transactionMetrics
        let networkCount = transactions.filter { $0.resourceFetchType != .localCache }.count
        let cacheCount = transactions.count - networkCount
        let dnsMilliseconds = Self.totalMilliseconds(
            transactions,
            start: \.domainLookupStartDate,
            end: \.domainLookupEndDate
        )
        let connectMilliseconds = Self.totalMilliseconds(
            transactions,
            start: \.connectStartDate,
            end: \.connectEndDate
        )
        let tlsMilliseconds = Self.totalMilliseconds(
            transactions,
            start: \.secureConnectionStartDate,
            end: \.secureConnectionEndDate
        )
        let responseMilliseconds = Self.totalMilliseconds(
            transactions,
            start: \.requestStartDate,
            end: \.responseStartDate
        )
        let taskMilliseconds = Int(metrics.taskInterval.duration * 1_000)
        let productName = self.productName
        let attemptNumber = self.attemptNumber

        signposter.emitEvent(
            "URLSession task metrics",
            id: signpostID,
            "product=\(productName) attempt=\(attemptNumber) task_ms=\(taskMilliseconds) network=\(networkCount) cache=\(cacheCount) dns_ms=\(dnsMilliseconds) connect_ms=\(connectMilliseconds) tls_ms=\(tlsMilliseconds) response_ms=\(responseMilliseconds)"
        )
    }

    private static func totalMilliseconds(
        _ transactions: [URLSessionTaskTransactionMetrics],
        start: KeyPath<URLSessionTaskTransactionMetrics, Date?>,
        end: KeyPath<URLSessionTaskTransactionMetrics, Date?>
    ) -> Int {
        transactions.reduce(0) { total, transaction in
            guard let start = transaction[keyPath: start],
                  let end = transaction[keyPath: end] else { return total }
            return total + max(0, Int(end.timeIntervalSince(start) * 1_000))
        }
    }
}

private struct HTTPStatusFailure: Error {
    let statusCode: Int
    let retryAfter: Duration?
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

enum ProviderError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)
    case missingRequiredData(String)
    case notConfigured(String)
    case deadlineExceeded

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
        case .deadlineExceeded:
            "The weather service did not respond within its request budget."
        }
    }
}
