import MapKit
import SwiftUI

struct RadarView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var playback = RadarPlaybackState()
    @State private var isLoadingRadar = false
    @State private var radarError: String?
    @State private var recenterToken = 0
    @State private var headerHeight: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0
    @State private var prefetchProgress: Double = 0

    private let radarProvider = NOAARadarProvider(capabilitiesCache: .shared)
    private let forecastProvider = HRRRForecastRadarProvider()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadarMapView(
                    location: store.screenState.location,
                    frames: playback.frames,
                    selectedFrameID: playback.selectedFrame?.id,
                    recenterToken: recenterToken,
                    legalInsets: UIEdgeInsets(
                        top: proxy.safeAreaInsets.top + headerHeight + 16,
                        left: 12,
                        bottom: proxy.safeAreaInsets.bottom + controlsHeight + 20,
                        right: 12
                    ),
                    onPrefetchUpdate: { update in
                        prefetchProgress = update.progress
                        playback.readyFrameIDs = update.readyFrameIDs
                    }
                )
                .ignoresSafeArea()

                VStack(spacing: WeatherTheme.sectionSpacing) {
                    RadarHeader(
                        location: store.screenState.location,
                        isLoading: isLoadingRadar,
                        onRecenter: { recenterToken += 1 },
                        onRefresh: {
                            Task { await loadRadar() }
                        }
                    )
                    .onHeightChange { headerHeight = $0 }

                    Spacer()

                    VStack(spacing: WeatherTheme.sectionSpacing) {
                        if isLoadingRadar && playback.frames.isEmpty {
                            RadarStatusCard(
                                icon: nil,
                                title: "Loading radar",
                                message: "Finding the latest radar scans."
                            )
                        } else if let radarError, playback.frames.isEmpty {
                            RadarStatusCard(
                                icon: "antenna.radiowaves.left.and.right",
                                title: "Radar unavailable",
                                message: radarError
                            )
                        }

                        RadarPlaybackControls(
                            playback: playback,
                            loadingProgress: prefetchProgress
                        )
                    }
                    .onHeightChange { controlsHeight = $0 }
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: WeatherRequestLocationKey(store.screenState.location)) {
            recenterToken += 1
            await loadRadar()
        }
        .task(id: playback.isPlaying) {
            guard playback.isPlaying else { return }

            while playback.isPlaying && !Task.isCancelled {
                let pause: Int
                if playback.selectedIndex == playback.frames.count - 1 {
                    pause = 1_600
                } else if playback.selectedIndex == playback.latestObservedIndex {
                    pause = 1_100
                } else {
                    pause = 600
                }
                try? await Task.sleep(for: .milliseconds(pause))

                var buffered = 0
                while !playback.isNextFrameReady && buffered < 2_500
                        && playback.isPlaying && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    buffered += 100
                }

                guard playback.isPlaying && !Task.isCancelled else { break }
                playback.advance()
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled {
                playback.isPlaying = false
            }
        }
    }

    @MainActor
    private func loadRadar() async {
        playback.isPlaying = false
        isLoadingRadar = true
        radarError = nil

        let location = store.screenState.location
        let forecastProvider = forecastProvider
        let forecastTask = Task {
            (try? await forecastProvider.frames(for: location, after: nil)) ?? []
        }

        do {
            let observed = try await radarProvider.frames(for: location)
            playback.replaceFrames(observed)

            if observed.isEmpty {
                radarError = "Radar did not return any recent frames."
            }

            isLoadingRadar = false

            let latestScan = observed.last?.timestamp ?? .distantPast
            let forecast = await forecastTask.value.filter { $0.timestamp > latestScan }

            guard !forecast.isEmpty,
                  WeatherRequestLocationKey(store.screenState.location)
                    == WeatherRequestLocationKey(location) else { return }

            let wasPlaying = playback.isPlaying
            let selectedID = playback.selectedFrame?.id
            playback.replaceFrames(observed + forecast)
            if let selectedID, let index = playback.frames.firstIndex(where: { $0.id == selectedID }) {
                playback.select(index: index)
            }
            playback.isPlaying = wasPlaying
        } catch {
            forecastTask.cancel()
            radarError = error.localizedDescription
            isLoadingRadar = false
        }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    func onHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(HeightPreferenceKey.self, perform: action)
    }
}

private struct RadarHeader: View {
    let location: WeatherLocation
    let isLoading: Bool
    let onRecenter: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Radar")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WeatherTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(location.displayName)
                    .font(.subheadline)
                    .foregroundStyle(WeatherTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            headerButton(action: onRefresh, label: "Refresh radar") {
                if isLoading {
                    ProgressView()
                        .tint(WeatherTheme.accent)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isLoading)

            headerButton(action: onRecenter, label: "Recenter radar map") {
                Image(systemName: "location.fill")
            }
        }
        .padding(.horizontal, WeatherTheme.cardPadding)
        .padding(.vertical, 12)
        .weatherSurface()
    }

    private func headerButton<Content: View>(
        action: @escaping () -> Void,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WeatherTheme.accent)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(WeatherTheme.insetFill)
                        .overlay(Circle().strokeBorder(WeatherTheme.insetStroke, lineWidth: 1))
                }
        }
        .accessibilityLabel(label)
    }
}

private struct RadarStatusCard: View {
    let icon: String?
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(WeatherTheme.accent)
                } else {
                    ProgressView()
                        .tint(WeatherTheme.accent)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeatherTheme.primaryText)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .weatherSurface(cornerRadius: WeatherTheme.smallRadius + 2)
        .accessibilityElement(children: .combine)
    }
}
