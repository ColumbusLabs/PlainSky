import Observation
import SwiftUI

@MainActor
@Observable
final class WeatherStore {
    var snapshot: WeatherSnapshot
    var savedLocations: [WeatherLocation]
    var isRefreshing = false
    var lastRefreshError: String?
    var isShowingPlaceholderData: Bool

    var unitSystem: WeatherUnitSystem {
        didSet {
            preferences.saveUnitSystem(unitSystem)
        }
    }

    private let repository: any WeatherRepository
    private let preferences: WeatherPreferences
    private let masksStaleLocationData: Bool
    private let cachesSnapshots: Bool
    private var loadGeneration = 0
    private var activeLoad: Task<Void, Never>?

    init(
        repository: (any WeatherRepository)? = nil,
        snapshot: WeatherSnapshot = MockWeather.snapshot,
        savedLocations: [WeatherLocation]? = nil,
        preferences: WeatherPreferences? = nil,
        isShowingPlaceholderData: Bool = false,
        masksStaleLocationData: Bool = false,
        cachesSnapshots: Bool = false
    ) {
        let resolvedPreferences = preferences ?? .live

        self.repository = repository ?? PreviewWeatherRepository()
        self.preferences = resolvedPreferences
        self.isShowingPlaceholderData = isShowingPlaceholderData
        self.masksStaleLocationData = masksStaleLocationData
        self.cachesSnapshots = cachesSnapshots
        self.unitSystem = resolvedPreferences.loadUnitSystem() ?? .us
        self.savedLocations = savedLocations
            ?? resolvedPreferences.loadSavedLocations()
            ?? MockWeather.savedLocations

        var initialSnapshot = snapshot
        if let lastLocation = resolvedPreferences.loadLastLocation() {
            initialSnapshot.location = lastLocation
        }
        self.snapshot = initialSnapshot
    }

    func refreshIfNeeded(maxAge: TimeInterval = 10 * 60) async {
        guard !isRefreshing else { return }

        let age = Date().timeIntervalSince(snapshot.fetchedAt)
        let hasPendingProducts = snapshot.availability.values
            .contains { $0.isLoading }

        guard age >= maxAge || hasPendingProducts else { return }

        await refresh()
    }

    func refresh() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedLocation = snapshot.location

        activeLoad?.cancel()

        let load = Task {
            await performRefresh(
                generation: generation,
                location: requestedLocation
            )
        }
        activeLoad = load
        await load.value
    }

    private func performRefresh(
        generation: Int,
        location requestedLocation: WeatherLocation
    ) async {
        guard generation == loadGeneration else { return }

        isRefreshing = true
        lastRefreshError = nil

        do {
            let loadedSnapshot = try await repository.load(
                location: requestedLocation
            ) { primarySnapshot in
                guard generation == self.loadGeneration,
                      self.snapshot.location.id == requestedLocation.id else {
                    return
                }

                self.snapshot = primarySnapshot
                self.isShowingPlaceholderData = false
                self.isRefreshing = false
                self.cache(primarySnapshot)
            }

            guard generation == loadGeneration,
                  snapshot.location.id == requestedLocation.id else {
                return
            }

            snapshot = loadedSnapshot
            isShowingPlaceholderData = false
            cache(loadedSnapshot)
        } catch {
            guard generation == loadGeneration else { return }
            lastRefreshError = error.localizedDescription
            resolvePendingProducts(with: error.localizedDescription)
        }

        if generation == loadGeneration {
            isRefreshing = false
        }
    }

    func select(_ location: WeatherLocation) {
        invalidateOutstandingLoad()

        if masksStaleLocationData && snapshot.location.id != location.id {
            isShowingPlaceholderData = true
            lastRefreshError = nil
        }

        snapshot.location = location
        preferences.saveLastLocation(location)
    }

    func selectAndRefresh(_ location: WeatherLocation) {
        select(location)
        Task {
            await refresh()
        }
    }

    func setCurrentLocation(_ location: WeatherLocation) {
        var location = location
        location.isCurrentLocation = true

        if let index = savedLocations.firstIndex(where: { $0.isCurrentLocation }) {
            savedLocations[index] = location
            if index != 0 {
                let updated = savedLocations.remove(at: index)
                savedLocations.insert(updated, at: 0)
            }
        } else {
            savedLocations.insert(location, at: 0)
        }

        persistLocations()
        select(location)
    }

    func setCurrentLocationAndRefresh(_ location: WeatherLocation) {
        setCurrentLocation(location)
        Task {
            await refresh()
        }
    }

    func addLocation(_ location: WeatherLocation) {
        if let existing = savedLocations.first(where: {
            abs($0.latitude - location.latitude) < 0.001 &&
            abs($0.longitude - location.longitude) < 0.001
        }) {
            select(existing)
            return
        }

        savedLocations.append(location)
        persistLocations()
        select(location)
    }

    func addLocationAndRefresh(_ location: WeatherLocation) {
        addLocation(location)
        Task {
            await refresh()
        }
    }

    func renameLocation(_ location: WeatherLocation, to proposedName: String) {
        guard !location.isCurrentLocation,
              let index = savedLocations.firstIndex(where: { $0.id == location.id }) else {
            return
        }

        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        savedLocations[index].name = trimmed
        let renamed = savedLocations[index]
        persistLocations()

        if snapshot.location.id == renamed.id {
            snapshot.location = renamed
            preferences.saveLastLocation(renamed)
        }
    }

    func canMoveLocation(_ location: WeatherLocation, offset: Int) -> Bool {
        guard !location.isCurrentLocation,
              let index = savedLocations.firstIndex(where: { $0.id == location.id }) else {
            return false
        }

        let target = index + offset
        guard savedLocations.indices.contains(target) else { return false }

        return !savedLocations[target].isCurrentLocation
    }

    func moveLocation(_ location: WeatherLocation, offset: Int) {
        guard canMoveLocation(location, offset: offset),
              let index = savedLocations.firstIndex(where: { $0.id == location.id }) else {
            return
        }

        savedLocations.swapAt(index, index + offset)
        persistLocations()
    }

    func removeLocation(_ location: WeatherLocation) {
        guard !location.isCurrentLocation else { return }

        let wasSelected = snapshot.location.id == location.id
        savedLocations.removeAll { $0.id == location.id }
        persistLocations()

        if wasSelected, let fallback = savedLocations.first {
            selectAndRefresh(fallback)
        }
    }

    func clearRefreshError() {
        lastRefreshError = nil
    }

    private func invalidateOutstandingLoad() {
        activeLoad?.cancel()
        loadGeneration += 1
        isRefreshing = false
    }

    private func resolvePendingProducts(with message: String) {
        let pendingProducts = snapshot.availability
            .filter { $0.value.isLoading }
            .map(\.key)

        guard !pendingProducts.isEmpty else { return }

        var updated = snapshot
        for product in pendingProducts {
            updated.availability[product] = .unavailable(message)
        }
        snapshot = updated
    }

    private func persistLocations() {
        preferences.saveSavedLocations(savedLocations)
    }

    private func cache(_ snapshot: WeatherSnapshot) {
        guard cachesSnapshots else { return }
        preferences.saveCachedSnapshot(snapshot)
    }
}
