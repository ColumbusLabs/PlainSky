@preconcurrency import MapKit
import Observation
import SwiftUI

struct LocationSearchView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var searchModel = LocationSearchModel()

    var onSelection: ((WeatherLocation) -> Void)?

    init(onSelection: ((WeatherLocation) -> Void)? = nil) {
        self.onSelection = onSelection
    }

    var body: some View {
        List {
            if searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Find a place",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Search for a city, town, or ZIP code.")
                )
                .listRowBackground(Color.clear)
            } else if searchModel.results.isEmpty && !searchModel.isSearching {
                ContentUnavailableView.search(text: searchModel.query)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(searchModel.results) { result in
                    Button {
                        Task {
                            if let location = await searchModel.resolve(result) {
                                store.addLocation(location)
                                onSelection?(location)
                                dismiss()
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.headline)

                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .disabled(searchModel.isResolving)
                }
            }
        }
        .navigationTitle("Add Place")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchModel.query, prompt: "City or ZIP code")
        .overlay {
            if searchModel.isResolving {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

struct LocationSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion
}

@MainActor
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            completer.queryFragment = query
        }
    }

    var results: [LocationSearchResult] = []
    var isSearching = false
    var isResolving = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        isSearching = false
        results = completer.results.prefix(20).map { completion in
            LocationSearchResult(
                id: completion.title + "|" + completion.subtitle,
                title: completion.title,
                subtitle: completion.subtitle,
                completion: completion
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isSearching = false
        results = []
    }

    func resolve(_ result: LocationSearchResult) async -> WeatherLocation? {
        isResolving = true
        defer { isResolving = false }

        let request = MKLocalSearch.Request(completion: result.completion)

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return nil }

            let coordinate = item.placemark.coordinate
            let region = [
                item.placemark.administrativeArea,
                item.placemark.country
            ]
            .compactMap { $0 }
            .first ?? result.subtitle

            return WeatherLocation(
                name: item.name ?? result.title,
                region: region,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            return nil
        }
    }
}
