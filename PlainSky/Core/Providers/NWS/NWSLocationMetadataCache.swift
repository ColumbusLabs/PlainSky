import Foundation

struct NWSMetadataCachePolicy: Equatable, Sendable {
    let allowsStorage: Bool
    let maxAge: TimeInterval?
    let age: TimeInterval

    init(response: HTTPURLResponse) {
        let directives = (response.value(forHTTPHeaderField: "Cache-Control") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let noStore = directives.contains { $0 == "no-store" }
        let noCache = directives.contains { $0 == "no-cache" }
        let maxAge = directives.first(where: { $0.hasPrefix("max-age=") })
            .flatMap { directive -> TimeInterval? in
                let value = directive.dropFirst("max-age=".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard let seconds = TimeInterval(value), seconds >= 0 else { return nil }
                return seconds
            }

        allowsStorage = !noStore && !noCache && maxAge != 0
        self.maxAge = maxAge
        age = max(0, TimeInterval(response.value(forHTTPHeaderField: "Age") ?? "0") ?? 0)
    }

    static let applicationDefault = NWSMetadataCachePolicy(
        allowsStorage: true,
        maxAge: nil,
        age: 0
    )

    private init(allowsStorage: Bool, maxAge: TimeInterval?, age: TimeInterval) {
        self.allowsStorage = allowsStorage
        self.maxAge = maxAge
        self.age = age
    }

    func expirationDate(validatedAt: Date, applicationTTL: TimeInterval) -> Date? {
        guard allowsStorage else { return nil }
        let lifetime = min(applicationTTL, maxAge ?? applicationTTL) - age
        guard lifetime > 0 else { return nil }
        return validatedAt.addingTimeInterval(lifetime)
    }
}

struct NWSMetadataCacheResult<Value: Sendable>: Sendable {
    let value: Value
    let policy: NWSMetadataCachePolicy

    init(value: Value, policy: NWSMetadataCachePolicy = .applicationDefault) {
        self.value = value
        self.policy = policy
    }
}

actor NWSLocationMetadataCache {
    static let live = NWSLocationMetadataCache(fileURL: defaultFileURL)

    private struct Key: Hashable, Codable, Sendable {
        let latitudeBits: UInt64
        let longitudeBits: UInt64

        init(_ location: WeatherLocation) {
            latitudeBits = location.latitude.bitPattern
            longitudeBits = location.longitude.bitPattern
        }
    }

    private struct StationKey: Hashable, Sendable {
        let location: Key
        let routeRevision: String
    }

    private struct Station: Codable, Sendable {
        let identifier: String
        let name: String

        init(_ properties: NWSStationProperties) {
            identifier = properties.stationIdentifier
            name = properties.name
        }

        var properties: NWSStationProperties {
            NWSStationProperties(stationIdentifier: identifier, name: name)
        }
    }

    private struct Entry: Codable, Sendable {
        let key: Key
        var gridID: String
        var gridX: Int
        var gridY: Int
        var forecastURL: String
        var hourlyURL: String
        var gridURL: String
        var stationsURL: String
        var timeZone: String?
        var pointValidatedAt: Date
        var pointCacheExpiresAt: Date?
        var stations: [Station]?
        var stationsValidatedAt: Date?
        var stationsCacheExpiresAt: Date?
        var stationRouteRevision: String?
        var lastAccessedAt: Date

        init(
            key: Key,
            point: NWSPointProperties,
            validatedAt: Date,
            cacheExpiresAt: Date?
        ) {
            self.key = key
            gridID = point.gridId
            gridX = point.gridX
            gridY = point.gridY
            forecastURL = point.forecast.absoluteString
            hourlyURL = point.forecastHourly.absoluteString
            gridURL = point.forecastGridData.absoluteString
            stationsURL = point.observationStations.absoluteString
            timeZone = point.timeZone
            pointValidatedAt = validatedAt
            pointCacheExpiresAt = cacheExpiresAt
            stations = nil
            stationsValidatedAt = nil
            stationsCacheExpiresAt = nil
            stationRouteRevision = nil
            lastAccessedAt = validatedAt
        }

        var point: NWSPointProperties? {
            guard let forecast = URL(string: forecastURL),
                  let hourly = URL(string: hourlyURL),
                  let grid = URL(string: gridURL),
                  let stations = URL(string: stationsURL) else {
                return nil
            }
            return NWSPointProperties(
                gridId: gridID,
                gridX: gridX,
                gridY: gridY,
                forecast: forecast,
                forecastHourly: hourly,
                forecastGridData: grid,
                observationStations: stations,
                timeZone: timeZone
            )
        }

        var stationProperties: [NWSStationProperties]? {
            stations?.map(\.properties)
        }

        var routeRevision: String { "\(gridID):\(gridX):\(gridY)" }
    }

    private struct Persisted: Codable, Sendable {
        let schemaVersion: Int
        var entries: [Entry]
    }

    private static let schemaVersion = 1
    private static let maximumEntries = 20

    private let fileURL: URL?
    private let timeToLive: TimeInterval
    private let now: @Sendable () -> Date
    private var entries: [Key: Entry]
    private var pointLoads: [Key: Task<NWSMetadataCacheResult<NWSPointProperties>, Error>] = [:]
    private var stationLoads: [
        StationKey: Task<NWSMetadataCacheResult<[NWSStationProperties]>, Error>
    ] = [:]

    init(
        fileURL: URL? = nil,
        timeToLive: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.timeToLive = timeToLive
        self.now = now
        entries = Self.readEntries(from: fileURL)
    }

    func point(
        for location: WeatherLocation,
        load: @escaping @Sendable () async throws -> NWSMetadataCacheResult<NWSPointProperties>
    ) async throws -> NWSPointProperties {
        let key = Key(location)
        if var entry = validEntry(for: key), let point = entry.point {
            WeatherInstrumentation.mark("NWS point metadata cache hit")
            entry.lastAccessedAt = now()
            entries[key] = entry
            persist()
            return point
        }

        if let pending = pointLoads[key] {
            WeatherInstrumentation.mark("NWS point metadata request coalesced")
            return try await pending.value.value
        }

        WeatherInstrumentation.mark("NWS point metadata cache miss")
        let pending = Task { try await load() }
        pointLoads[key] = pending
        do {
            let result = try await pending.value
            if result.policy.expirationDate(validatedAt: now(), applicationTTL: timeToLive) != nil {
                store(result.value, for: key, at: now(), policy: result.policy)
            } else {
                entries[key] = nil
                persist()
            }
            pointLoads[key] = nil
            return result.value
        } catch {
            pointLoads[key] = nil
            throw error
        }
    }

    func stationDirectory(
        for location: WeatherLocation,
        routeRevision: String,
        load: @escaping @Sendable () async throws -> NWSMetadataCacheResult<[NWSStationProperties]>
    ) async throws -> [NWSStationProperties] {
        let key = Key(location)
        let stationKey = StationKey(location: key, routeRevision: routeRevision)
        if var entry = validEntry(for: key),
           entry.routeRevision == routeRevision,
           entry.stationRouteRevision == routeRevision,
           let validatedAt = entry.stationsValidatedAt,
           isFresh(validatedAt: validatedAt, expiresAt: entry.stationsCacheExpiresAt),
           let stations = entry.stationProperties {
            WeatherInstrumentation.mark("NWS station directory cache hit")
            entry.lastAccessedAt = now()
            entries[key] = entry
            persist()
            return stations
        }

        if let pending = stationLoads[stationKey] {
            WeatherInstrumentation.mark("NWS station directory request coalesced")
            return try await pending.value.value
        }

        WeatherInstrumentation.mark("NWS station directory cache miss")
        let pending = Task { try await load() }
        stationLoads[stationKey] = pending
        do {
            let result = try await pending.value
            let stations = result.value
            if var entry = entries[key], entry.routeRevision == routeRevision {
                if let cacheExpiresAt = result.policy.expirationDate(
                    validatedAt: now(),
                    applicationTTL: timeToLive
                ) {
                    entry.stations = stations.map(Station.init)
                    entry.stationRouteRevision = routeRevision
                    entry.stationsValidatedAt = now()
                    entry.stationsCacheExpiresAt = cacheExpiresAt
                    entry.lastAccessedAt = now()
                } else {
                    entry.stations = nil
                    entry.stationRouteRevision = nil
                    entry.stationsValidatedAt = nil
                    entry.stationsCacheExpiresAt = nil
                }
                entries[key] = entry
                persist()
            }
            stationLoads[stationKey] = nil
            return stations
        } catch {
            stationLoads[stationKey] = nil
            throw error
        }
    }

    func invalidate(_ location: WeatherLocation) {
        entries[Key(location)] = nil
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    private func validEntry(for key: Key) -> Entry? {
        guard let entry = entries[key] else { return nil }
        guard isFresh(validatedAt: entry.pointValidatedAt, expiresAt: entry.pointCacheExpiresAt),
              entry.point != nil else {
            entries[key] = nil
            persist()
            return nil
        }
        return entry
    }

    private func isFresh(validatedAt: Date, expiresAt: Date?) -> Bool {
        let currentTime = now()
        let age = currentTime.timeIntervalSince(validatedAt)
        // HTTP semantics: an entry is fresh strictly before its lifetime ends.
        return age >= 0
            && age < timeToLive
            && (expiresAt.map { $0 > currentTime } ?? true)
    }

    private func store(
        _ point: NWSPointProperties,
        for key: Key,
        at date: Date,
        policy: NWSMetadataCachePolicy
    ) {
        let prior = entries[key]
        var entry = Entry(
            key: key,
            point: point,
            validatedAt: date,
            cacheExpiresAt: policy.expirationDate(validatedAt: date, applicationTTL: timeToLive)
        )
        if prior?.routeRevision == entry.routeRevision {
            entry.stations = prior?.stations
            entry.stationsValidatedAt = prior?.stationsValidatedAt
            entry.stationsCacheExpiresAt = prior?.stationsCacheExpiresAt
            entry.stationRouteRevision = prior?.stationRouteRevision
        }
        entries[key] = entry
        trimToCapacity()
        persist()
    }

    private func trimToCapacity() {
        let overflow = entries.count - Self.maximumEntries
        guard overflow > 0 else { return }
        let leastRecentKeys = entries.values
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
            .prefix(overflow)
            .map(\.key)
        for key in leastRecentKeys {
            entries[key] = nil
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let value = Persisted(schemaVersion: Self.schemaVersion, entries: Array(entries.values))
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL, options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
            #endif
        } catch {
            // Routing metadata is an optimization. Persistence failure leaves
            // the in-memory refresh successful and turns the next launch into a miss.
        }
    }

    private static func readEntries(from fileURL: URL?) -> [Key: Entry] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let persisted = try? JSONDecoder().decode(Persisted.self, from: data),
              persisted.schemaVersion == schemaVersion else {
            return [:]
        }
        var result: [Key: Entry] = [:]
        for entry in persisted.entries {
            result[entry.key] = entry
        }
        return result
    }

    private static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("PlainSky/NWSLocationMetadata-v1.json", isDirectory: false)
    }
}
