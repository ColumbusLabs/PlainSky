import Foundation

struct NWSWeatherProvider: PrimaryWeatherProviding, Sendable {
    private let client: NWSAPIClient
    private let metadataCache: NWSLocationMetadataCache
    private let now: @Sendable () -> Date

    init(
        client: NWSAPIClient = NWSAPIClient(),
        metadataCache: NWSLocationMetadataCache = NWSLocationMetadataCache(fileURL: nil),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.metadataCache = metadataCache
        self.now = now
    }

    func updates(
        for location: WeatherLocation,
        context: WeatherRefreshContext,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) async throws {
        let client = self.client
        let metadataCache = self.metadataCache
        let now = self.now
        let identity = context.identity
        let routingContext = context.requestContext(for: .routingMetadata)
        let alertsContext = context.requestContext(for: .alerts)
        let dailyContext = context.requestContext(for: .dailyForecast)
        let hourlyContext = context.requestContext(for: .hourlyForecast)
        let gridContext = context.requestContext(for: .gridEnrichment)
        let currentDeadline = context.monotonicStart.advanced(by: context.requestBudgets.current)
        let currentResolution = NWSCurrentProductResolution()
        let routeRecovery = NWSRouteRecovery(
            location: location,
            metadataCache: metadataCache,
            client: client,
            routingContext: routingContext,
            identity: identity,
            onUpdate: onUpdate
        )
        let currentDeadlineTask = Task {
            do {
                try await ContinuousClock().sleep(until: currentDeadline)
            } catch {
                return
            }
            guard await currentResolution.claim() else { return }
            await onUpdate(WeatherProductUpdate(
                identity: identity,
                event: .current(.unavailable("No fresh usable NWS station observation was available."))
            ))
        }
        defer { currentDeadlineTask.cancel() }

        await withTaskCancellationHandler {
            await withTaskGroup(of: NWSProviderWorkResult.self) { group in
                // Coordinate-based alerts can complete without waiting for /points.
                group.addTask {
                    do {
                        let response = try await client.activeAlerts(
                            for: location,
                            context: alertsContext
                        )
                        let validatedAt = now()
                        let alerts = WeatherInstrumentation.measure("NWS alert mapping") {
                            NWSMapper.alerts(collection: response, fetchedAt: validatedAt)
                        }
                        let source = alerts.first?.source ?? Self.sourceMetadata(
                            provider: .nwsForecast,
                            productName: "NWS active alerts",
                            validatedAt: validatedAt
                        )
                        return .alerts(.available(
                            alerts,
                            WeatherValidationMetadata(source: source, validatedAt: validatedAt)
                        ))
                    } catch {
                        return .alerts(.unavailable("Unable to check National Weather Service alerts."))
                    }
                }

                group.addTask {
                    do {
                        let point = try await metadataCache.point(for: location) {
                            try await client.pointMetadata(
                                for: location,
                                context: routingContext
                            )
                        }
                        return .point(.success(point))
                    } catch {
                        return .point(.failure(NWSProviderFailure(
                            message: "Unable to resolve the NWS forecast location."
                        )))
                    }
                }

                // A stale route is re-resolved at most once per refresh, so a
                // product can be produced on at most two routes. Results from a
                // superseded route are never published; the product is fetched
                // again on the current route instead.
                var initialRoute: NWSPointProperties?
                var activeRevision: String?
                var deliveredRevisions: [NWSRouteProduct: String] = [:]
                var refetchedProducts = Set<NWSRouteProduct>()
                var hourly: (response: NWSForecastResponse, items: [HourlyForecastItem], sourceName: String)?
                var grid: NWSGridpointProperties?

                for await result in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        return
                    }

                    if let product = result.routeProduct, let initialRoute {
                        let latestRoute = await routeRecovery.latestRoute() ?? initialRoute
                        let latestRevision = Self.routeRevision(for: latestRoute)

                        if result.routeRevision != latestRevision {
                            if refetchedProducts.insert(product).inserted {
                                group.addTask(operation: Self.work(
                                    for: product,
                                    route: latestRoute,
                                    client: client,
                                    recovery: routeRecovery,
                                    now: now,
                                    dailyContext: dailyContext,
                                    hourlyContext: hourlyContext,
                                    gridContext: gridContext
                                ))
                            }
                            continue
                        }

                        if latestRevision != activeRevision {
                            activeRevision = latestRevision
                            hourly = nil
                            grid = nil
                            for (delivered, revision) in deliveredRevisions
                            where revision != latestRevision && refetchedProducts.insert(delivered).inserted {
                                group.addTask(operation: Self.work(
                                    for: delivered,
                                    route: latestRoute,
                                    client: client,
                                    recovery: routeRecovery,
                                    now: now,
                                    dailyContext: dailyContext,
                                    hourlyContext: hourlyContext,
                                    gridContext: gridContext
                                ))
                            }
                        }
                        deliveredRevisions[product] = latestRevision
                    }

                    switch result {
                    case let .alerts(state):
                        await onUpdate(WeatherProductUpdate(
                            identity: identity,
                            event: .alerts(state)
                        ))

                    case let .point(.success(properties)):
                        let revision = Self.routeRevision(for: properties)
                        initialRoute = properties
                        activeRevision = revision
                        await routeRecovery.setInitialRoute(properties)
                        await onUpdate(WeatherProductUpdate(
                            identity: identity,
                            sourceRevision: revision,
                            event: .routeRevision(
                                revision,
                                timeZoneIdentifier: properties.timeZone
                            )
                        ))

                        for product in NWSRouteProduct.allCases {
                            group.addTask(operation: Self.work(
                                for: product,
                                route: properties,
                                client: client,
                                recovery: routeRecovery,
                                now: now,
                                dailyContext: dailyContext,
                                hourlyContext: hourlyContext,
                                gridContext: gridContext
                            ))
                        }

                        group.addTask {
                            let value = await Self.currentConditionsWithRouteRecovery(
                                client: client,
                                metadataCache: metadataCache,
                                location: location,
                                initialRoute: properties,
                                routeRecovery: routeRecovery,
                                now: now,
                                context: context
                            )
                            return .current(value.value, value.revision)
                        }

                    case .point(.failure):
                        await onUpdate(WeatherProductUpdate(
                            identity: identity,
                            event: .hourly(.unavailable("Unable to refresh the NWS hourly forecast."))
                        ))
                        await onUpdate(WeatherProductUpdate(
                            identity: identity,
                            event: .daily(.unavailable("Unable to refresh the NWS daily forecast."))
                        ))
                        if await currentResolution.claim() {
                            await onUpdate(WeatherProductUpdate(
                                identity: identity,
                                event: .current(.unavailable("No fresh usable NWS station observation was available."))
                            ))
                        }

                    case let .daily(state, revision):
                        await onUpdate(WeatherProductUpdate(
                            identity: identity,
                            sourceRevision: revision,
                            event: .daily(state)
                        ))

                    case let .hourly(response, items, sourceName, revision, validatedAt):
                        hourly = (response, items, sourceName)
                        await onUpdate(WeatherProductUpdate(
                            identity: identity,
                            sourceRevision: revision,
                            event: .hourly(Self.hourlyState(
                                items,
                                validatedAt: validatedAt,
                                revision: revision
                            ))
                        ))
                        if let grid {
                            await publishEnrichedHourly(
                                response: response,
                                base: items,
                                grid: grid,
                                sourceName: sourceName,
                                revision: revision,
                                onUpdate: onUpdate,
                                identity: identity
                            )
                        }

                    case let .hourlyFailure(message, revision):
                        hourly = nil
                        await onUpdate(WeatherProductUpdate(
                            identity: identity,
                            sourceRevision: revision,
                            event: .hourly(.unavailable(message))
                        ))

                    case let .grid(value, revision):
                        grid = value
                        if let hourly {
                            await publishEnrichedHourly(
                                response: hourly.response,
                                base: hourly.items,
                                grid: value,
                                sourceName: hourly.sourceName,
                                revision: revision,
                                onUpdate: onUpdate,
                                identity: identity
                            )
                        }

                    case .gridFailure:
                        // Base hourly conditions have already been delivered. Grid
                        // data only enriches fields that the forecast omits.
                        grid = nil

                    case let .current(value, revision):
                        guard await currentResolution.claim() else { continue }
                        let state: WeatherProductState<CurrentConditions>
                        if let value {
                            let validatedAt = now()
                            var source = value.source
                            source.validatedAt = validatedAt
                            state = .available(
                                value,
                                WeatherValidationMetadata(
                                    source: source,
                                    validatedAt: validatedAt,
                                    sourceRevision: revision
                                )
                            )
                        } else {
                            state = .unavailable("No fresh usable NWS station observation was available.")
                        }
                        await onUpdate(WeatherProductUpdate(
                            identity: identity,
                            sourceRevision: revision,
                            event: .current(state)
                        ))
                    }
                }
            }
        } onCancel: {
            Task { await routeRecovery.cancel() }
        }
    }

    private static func work(
        for product: NWSRouteProduct,
        route: NWSPointProperties,
        client: NWSAPIClient,
        recovery: NWSRouteRecovery,
        now: @escaping @Sendable () -> Date,
        dailyContext: HTTPRequestContext,
        hourlyContext: HTTPRequestContext,
        gridContext: HTTPRequestContext
    ) -> @Sendable () async -> NWSProviderWorkResult {
        switch product {
        case .daily:
            return {
                let fetched = await withRouteRecovery(initialRoute: route, recovery: recovery) { route in
                    try await client.forecast(url: route.forecast, context: dailyContext)
                }
                let route = fetched.route
                let revision = routeRevision(for: route)
                guard let response = fetched.value else {
                    return .daily(.unavailable("Unable to refresh the NWS daily forecast."), revision)
                }
                let validatedAt = now()
                let items = WeatherInstrumentation.measure("NWS daily mapping") {
                    NWSMapper.dailyForecast(
                        response: response,
                        timeZoneIdentifier: route.timeZone,
                        sourceName: "NWS \(route.gridId) forecast grid",
                        fetchedAt: validatedAt
                    )
                }
                guard let source = items.first?.source else {
                    return .daily(.unavailable("NWS returned no usable daily forecast periods."), revision)
                }
                return .daily(.available(
                    items,
                    WeatherValidationMetadata(
                        source: source,
                        validatedAt: validatedAt,
                        sourceRevision: revision
                    )
                ), revision)
            }

        case .hourly:
            return {
                let fetched = await withRouteRecovery(initialRoute: route, recovery: recovery) { route in
                    try await client.hourlyForecast(url: route.forecastHourly, context: hourlyContext)
                }
                let route = fetched.route
                let revision = routeRevision(for: route)
                guard let response = fetched.value else {
                    return .hourlyFailure("Unable to refresh the NWS hourly forecast.", revision)
                }
                let sourceName = "NWS \(route.gridId) forecast grid"
                let validatedAt = now()
                let items = WeatherInstrumentation.measure("NWS base hourly mapping") {
                    NWSMapper.hourlyForecast(
                        response: response,
                        grid: nil,
                        sourceName: sourceName,
                        fetchedAt: validatedAt
                    )
                }
                return .hourly(response, items, sourceName, revision, validatedAt)
            }

        case .grid:
            return {
                let fetched = await withRouteRecovery(initialRoute: route, recovery: recovery) { route in
                    try await client.gridData(url: route.forecastGridData, context: gridContext).properties
                }
                let revision = routeRevision(for: fetched.route)
                guard let grid = fetched.value else { return .gridFailure(revision) }
                return .grid(grid, revision)
            }
        }
    }

    func weather(for location: WeatherLocation) async throws -> PrimaryWeatherPayload {
        let fetchedAt = now()
        let point = try await client.point(for: location)
        let properties = point.properties

        async let forecastResponse = try? client.forecast(url: properties.forecast)
        async let hourlyResponse = try? client.hourlyForecast(url: properties.forecastHourly)
        async let gridResponse = try? client.gridData(url: properties.forecastGridData)
        async let alertCollection = try? client.activeAlerts(for: location)
        async let currentObservation = currentConditions(
            stationsURL: properties.observationStations,
            fetchedAt: fetchedAt,
            location: location,
            routeRevision: "\(properties.gridId):\(properties.gridX):\(properties.gridY)"
        )

        let dailyResponse = await forecastResponse
        let hourlyForecastResponse = await hourlyResponse
        let grid = await gridResponse
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

        let current = await currentObservation

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

    private static func sourceMetadata(
        provider: WeatherProvider,
        productName: String,
        validatedAt: Date
    ) -> WeatherSourceMetadata {
        WeatherSourceMetadata(
            provider: provider,
            productName: productName,
            sourceName: nil,
            observedAt: nil,
            issuedAt: nil,
            validFrom: nil,
            validTo: nil,
            fetchedAt: validatedAt,
            expiresAt: nil,
            validatedAt: validatedAt
        )
    }

    private static func hourlyState(
        _ items: [HourlyForecastItem],
        validatedAt: Date,
        revision: String
    ) -> WeatherProductState<[HourlyForecastItem]> {
        guard let source = items.first?.source else {
            return .unavailable("NWS returned no usable hourly forecast periods.")
        }
        return .available(
            items,
            WeatherValidationMetadata(
                source: source,
                validatedAt: validatedAt,
                sourceRevision: revision
            )
        )
    }

    fileprivate static func routeRevision(for point: NWSPointProperties) -> String {
        "\(point.gridId):\(point.gridX):\(point.gridY)"
    }

    private static func withRouteRecovery<Value: Sendable>(
        initialRoute: NWSPointProperties,
        recovery: NWSRouteRecovery,
        operation: @escaping @Sendable (NWSPointProperties) async throws -> Value
    ) async -> NWSRouteRequestOutcome<Value> {
        do {
            return NWSRouteRequestOutcome(
                value: try await operation(initialRoute),
                route: initialRoute
            )
        } catch {
            guard isInvalidRouteResponse(error) else {
                return NWSRouteRequestOutcome(value: nil, route: initialRoute)
            }
        }

        do {
            let refreshedRoute = try await recovery.resolveAfterInvalidRoute()
            do {
                return NWSRouteRequestOutcome(
                    value: try await operation(refreshedRoute),
                    route: refreshedRoute
                )
            } catch {
                return NWSRouteRequestOutcome(value: nil, route: refreshedRoute)
            }
        } catch {
            return NWSRouteRequestOutcome(
                value: nil,
                route: await recovery.latestRoute() ?? initialRoute
            )
        }
    }

    private static func isInvalidRouteResponse(_ error: Error) -> Bool {
        guard case let ProviderError.httpStatus(statusCode) = error else { return false }
        return statusCode == 404 || statusCode == 410
    }

    private func publishEnrichedHourly(
        response: NWSForecastResponse,
        base: [HourlyForecastItem],
        grid: NWSGridpointProperties,
        sourceName: String,
        revision: String,
        onUpdate: @escaping WeatherProductUpdateHandler,
        identity: WeatherRefreshIdentity
    ) async {
        let enriched = WeatherInstrumentation.measure("NWS hourly enrichment mapping") {
            NWSMapper.hourlyForecast(
                response: response,
                grid: grid,
                sourceName: sourceName,
                fetchedAt: now()
            )
        }
        let stableItems = NWSMapper.preservingHourlyIdentity(from: base, in: enriched)
            .map { item in
                guard let baseItem = base.first(where: { $0.date == item.date }) else {
                    return item
                }
                var item = item
                item.source = baseItem.source
                return item
            }
        let validatedAt = base.first?.source.validatedAt
            ?? base.first?.source.fetchedAt
            ?? now()

        await onUpdate(WeatherProductUpdate(
            identity: identity,
            sourceRevision: revision,
            event: .hourly(Self.hourlyState(
                stableItems,
                validatedAt: validatedAt,
                revision: revision
            ))
        ))
    }

    private static let maximumStationCount = 5

    private static func currentConditionsWithRouteRecovery(
        client: NWSAPIClient,
        metadataCache: NWSLocationMetadataCache,
        location: WeatherLocation,
        initialRoute: NWSPointProperties,
        routeRecovery: NWSRouteRecovery,
        now: @escaping @Sendable () -> Date,
        context: WeatherRefreshContext
    ) async -> (value: CurrentConditions?, revision: String) {
        let directoryContext = context.requestContext(for: .stationDirectory)
        let directory = await withRouteRecovery(
            initialRoute: initialRoute,
            recovery: routeRecovery
        ) { route in
            try await metadataCache.stationDirectory(
                for: location,
                routeRevision: routeRevision(for: route),
                load: {
                    try await client.stationDirectoryMetadata(
                        url: route.observationStations,
                        context: directoryContext
                    )
                }
            )
        }

        let revision = routeRevision(for: directory.route)
        guard let directoryStations = directory.value else {
            return (nil, revision)
        }
        let stations = Array(directoryStations.prefix(maximumStationCount))
        guard !stations.isEmpty else { return (nil, revision) }

        let selector = NWSCurrentObservationSelector(
            client: client,
            stations: stations,
            now: now,
            refreshContext: context
        )
        let value = await withTaskCancellationHandler {
            await selector.firstUsable()
        } onCancel: {
            Task { await selector.cancel() }
        }
        return (value, revision)
    }

    private func currentConditions(
        stationsURL: URL,
        fetchedAt: Date,
        location: WeatherLocation,
        routeRevision: String
    ) async -> CurrentConditions? {
        _ = fetchedAt
        return await Self.currentConditions(
            client: client,
            metadataCache: metadataCache,
            location: location,
            stationsURL: stationsURL,
            now: now,
            context: nil,
            routeRevision: routeRevision
        )
    }

    private static func currentConditions(
        client: NWSAPIClient,
        metadataCache: NWSLocationMetadataCache,
        location: WeatherLocation,
        stationsURL: URL,
        now: @escaping @Sendable () -> Date,
        context: WeatherRefreshContext?,
        routeRevision: String
    ) async -> CurrentConditions? {
        let directoryContext = context?.requestContext(for: .stationDirectory)
        guard let directoryStations = try? await metadataCache.stationDirectory(
            for: location,
            routeRevision: routeRevision,
            load: {
                try await client.stationDirectoryMetadata(
                    url: stationsURL,
                    context: directoryContext
                )
            }
        ) else {
            return nil
        }

        let stations = Array(directoryStations.prefix(Self.maximumStationCount))
        guard !stations.isEmpty else { return nil }

        let selector = NWSCurrentObservationSelector(
            client: client,
            stations: stations,
            now: now,
            refreshContext: context
        )
        return await withTaskCancellationHandler {
            await selector.firstUsable()
        } onCancel: {
            Task { await selector.cancel() }
        }
    }

}

private actor NWSCurrentObservationSelector {
    private static let maximumConcurrentRequests = 2

    private let client: NWSAPIClient
    private let stations: [NWSStationProperties]
    private let now: @Sendable () -> Date
    private let refreshContext: WeatherRefreshContext?
    private var nextIndex = 0
    private var activeCount = 0
    private var completed = Set<Int>()
    private var results: [Int: CurrentConditions] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var continuation: CheckedContinuation<CurrentConditions?, Never>?
    private var finished = false

    init(
        client: NWSAPIClient,
        stations: [NWSStationProperties],
        now: @escaping @Sendable () -> Date,
        refreshContext: WeatherRefreshContext?
    ) {
        self.client = client
        self.stations = stations
        self.now = now
        self.refreshContext = refreshContext
    }

    func firstUsable() async -> CurrentConditions? {
        guard !finished else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            startNextCandidate()
            startNextCandidate()
        }
    }

    func cancel() {
        finish(with: nil)
    }

    private func startNextCandidate() {
        guard !finished,
              nextIndex < stations.count,
              activeCount < Self.maximumConcurrentRequests else { return }

        let index = nextIndex
        let station = stations[index]
        nextIndex += 1
        activeCount += 1
        let candidateContext = makeCandidateContext()
        let client = self.client
        let now = self.now
        tasks[index] = Task {
            let observation = try? await client.latestObservation(
                stationIdentifier: station.stationIdentifier,
                context: candidateContext
            )
            let value: CurrentConditions?
            if let observation {
                let validatedAt = now()
                value = WeatherInstrumentation.measure("NWS current mapping") {
                    NWSMapper.currentConditions(
                        station: station,
                        observation: observation,
                        fetchedAt: validatedAt,
                        now: validatedAt
                    )
                }
            } else {
                value = nil
            }
            self.candidateFinished(index: index, value: value)
        }
    }

    private func candidateFinished(index: Int, value: CurrentConditions?) {
        guard !finished else { return }
        tasks[index] = nil
        activeCount -= 1
        completed.insert(index)
        if let value {
            results[index] = value
        }

        // Keep station order while allowing a valid nearest observation to
        // return without joining slower, farther requests.
        for candidateIndex in stations.indices {
            guard completed.contains(candidateIndex) else { break }
            if let selected = results[candidateIndex] {
                finish(with: selected)
                return
            }
        }

        if completed.count == stations.count {
            finish(with: nil)
            return
        }
        startNextCandidate()
    }

    private func finish(with value: CurrentConditions?) {
        guard !finished else { return }
        finished = true
        let pending = Array(tasks.values)
        tasks.removeAll()
        pending.forEach { $0.cancel() }
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func makeCandidateContext() -> HTTPRequestContext? {
        guard let refreshContext else { return nil }
        let overall = refreshContext.requestContext(for: .currentConditions)
        let candidateDeadline = ContinuousClock().now.advanced(by: refreshContext.requestBudgets.currentCandidate)
        return HTTPRequestContext(
            product: .currentConditions,
            identity: refreshContext.identity,
            deadline: min(overall.deadline, candidateDeadline),
            retryPolicy: overall.retryPolicy,
            requiresRevalidation: true
        )
    }
}

private actor NWSCurrentProductResolution {
    private var isClaimed = false

    func claim() -> Bool {
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}

private struct NWSRouteRequestOutcome<Value: Sendable>: Sendable {
    let value: Value?
    let route: NWSPointProperties
}

private actor NWSRouteRecovery {
    private let location: WeatherLocation
    private let metadataCache: NWSLocationMetadataCache
    private let client: NWSAPIClient
    private let routingContext: HTTPRequestContext
    private let identity: WeatherRefreshIdentity
    private let onUpdate: WeatherProductUpdateHandler
    private var latestResolvedRoute: NWSPointProperties?
    private var recoveryTask: Task<NWSPointProperties, Error>?

    init(
        location: WeatherLocation,
        metadataCache: NWSLocationMetadataCache,
        client: NWSAPIClient,
        routingContext: HTTPRequestContext,
        identity: WeatherRefreshIdentity,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) {
        self.location = location
        self.metadataCache = metadataCache
        self.client = client
        self.routingContext = routingContext
        self.identity = identity
        self.onUpdate = onUpdate
    }

    func setInitialRoute(_ route: NWSPointProperties) {
        latestResolvedRoute = route
    }

    func latestRoute() -> NWSPointProperties? {
        latestResolvedRoute
    }

    func resolveAfterInvalidRoute() async throws -> NWSPointProperties {
        let task: Task<NWSPointProperties, Error>
        if let recoveryTask {
            task = recoveryTask
        } else {
            let location = self.location
            let metadataCache = self.metadataCache
            let client = self.client
            let routingContext = self.routingContext
            task = Task {
                await metadataCache.invalidate(location)
                return try await metadataCache.point(for: location) {
                    try await client.pointMetadata(for: location, context: routingContext)
                }
            }
            recoveryTask = task
        }

        let route = try await task.value
        let previousRevision = latestResolvedRoute.map {
            NWSWeatherProvider.routeRevision(for: $0)
        }
        let revision = NWSWeatherProvider.routeRevision(for: route)
        guard revision != previousRevision else { return route }
        latestResolvedRoute = route
        await onUpdate(WeatherProductUpdate(
            identity: identity,
            sourceRevision: revision,
            event: .routeRevision(revision, timeZoneIdentifier: route.timeZone)
        ))
        return route
    }

    func cancel() {
        recoveryTask?.cancel()
    }
}

private enum NWSRouteProduct: CaseIterable, Hashable, Sendable {
    case daily
    case hourly
    case grid
}

private enum NWSProviderWorkResult: Sendable {
    case alerts(WeatherProductState<[WeatherAlert]>)
    case point(Result<NWSPointProperties, NWSProviderFailure>)
    case daily(WeatherProductState<[DailyForecastItem]>, String)
    case hourly(NWSForecastResponse, [HourlyForecastItem], String, String, Date)
    case hourlyFailure(String, String)
    case grid(NWSGridpointProperties, String)
    case gridFailure(String)
    case current(CurrentConditions?, String)

    /// Forecast products that are fetched from a grid route and must be
    /// refetched when that route is superseded. Current conditions are keyed by
    /// station rather than grid and are resolved once per refresh.
    var routeProduct: NWSRouteProduct? {
        switch self {
        case .daily: .daily
        case .hourly, .hourlyFailure: .hourly
        case .grid, .gridFailure: .grid
        case .alerts, .point, .current: nil
        }
    }

    var routeRevision: String? {
        switch self {
        case let .daily(_, revision),
             let .hourly(_, _, _, revision, _),
             let .hourlyFailure(_, revision),
             let .grid(_, revision),
             let .gridFailure(revision):
            revision
        case .alerts, .point, .current:
            nil
        }
    }
}

private struct NWSProviderFailure: Error, Sendable {
    let message: String
}
