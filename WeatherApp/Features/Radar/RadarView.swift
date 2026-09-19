import MapKit
import SwiftUI

struct RadarView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var playback = RadarPlaybackState()
    @State private var isLoadingRadar = false
    @State private var radarError: String?
    @State private var recenterToken = 0

    private let radarProvider = NOAARadarProvider()

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .night)
                .zIndex(0)

            RadarMapView(
                location: store.snapshot.location,
                frame: playback.selectedFrame,
                recenterToken: recenterToken
            )
            .zIndex(1)

            VStack(spacing: 12) {
                RadarHeader(
                    location: store.snapshot.location,
                    isLoading: isLoadingRadar,
                    onRecenter: { recenterToken += 1 },
                    onRefresh: {
                        Task { await loadRadar() }
                    }
                )

                Spacer()

                if isLoadingRadar && playback.frames.isEmpty {
                    RadarLoadingCard()
                } else if let radarError, playback.frames.isEmpty {
                    RadarUnavailableCard(message: radarError)
                }

                RadarPlaybackControls(playback: playback)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .zIndex(2)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.snapshot.location.id) {
            recenterToken += 1
            await loadRadar()
        }
        .task(id: playback.isPlaying) {
            guard playback.isPlaying else { return }

            while playback.isPlaying && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(650))

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

        do {
            let frames = try await radarProvider.frames(for: store.snapshot.location)
            playback.replaceFrames(frames)

            if frames.isEmpty {
                radarError = "NOAA radar did not return any recent frames."
            }
        } catch {
            radarError = error.localizedDescription
        }

        isLoadingRadar = false
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
                    .font(.title2.bold())

                Text(location.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("NOAA")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())

            Button(action: onRefresh) {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.thinMaterial, in: Circle())
            }
            .disabled(isLoading)
            .accessibilityLabel("Refresh radar")

            Button(action: onRecenter) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Recenter radar map")
        }
        .foregroundStyle(.primary)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct RadarLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(WeatherTheme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("Loading NOAA radar")
                    .font(.subheadline.weight(.semibold))

                Text("Finding the latest advertised radar frames.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RadarUnavailableCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(WeatherTheme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("Radar unavailable")
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
