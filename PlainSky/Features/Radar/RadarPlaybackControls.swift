import SwiftUI

struct RadarPlaybackControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var playback: RadarPlaybackState
    var loadingProgress: Double = 1

    private var isPreparing: Bool {
        loadingProgress < 1 && playback.frames.count > 1
    }

    private var playbackDisabled: Bool {
        playback.frames.count < 2 || reduceMotion
    }

    private var isShowingForecast: Bool {
        playback.selectedFrame?.kind == .forecast
    }

    private var ageLabel: String {
        guard let frame = playback.selectedFrame else { return "No radar loaded" }

        switch frame.kind {
        case .observed:
            let minutes = Int(Date().timeIntervalSince(frame.timestamp) / 60)
            return minutes < 3 ? "Just now" : "\(Self.duration(minutes: minutes)) ago"

        case .forecast:
            let minutes = Int(frame.timestamp.timeIntervalSince(Date()) / 60)
            return minutes <= 0 ? "Model forecast" : "Model forecast · in \(Self.duration(minutes: minutes))"
        }
    }

    private static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(playback.selectedFrame.map { WeatherFormatters.hour($0.timestamp) } ?? "—")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(WeatherTheme.primaryText)
                            .contentTransition(.numericText())

                        if isShowingForecast {
                            Text("Forecast")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(WeatherTheme.accent, in: Capsule())
                        }
                    }

                    Text(ageLabel)
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.secondaryText)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 8)

                RadarLegend()
                    .frame(width: 128)
            }

            HStack(spacing: 12) {
                Button {
                    playback.togglePlayback()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            playbackDisabled ? WeatherTheme.tertiaryText : WeatherTheme.accent,
                            in: Circle()
                        )
                        .shadow(color: WeatherTheme.accent.opacity(playbackDisabled ? 0 : 0.35), radius: 6, y: 2)
                }
                .disabled(playbackDisabled)
                .accessibilityLabel(playback.isPlaying ? "Pause radar" : "Play radar")
                .accessibilityHint(
                    reduceMotion && playback.frames.count > 1
                        ? "Playback is disabled while Reduce Motion is enabled. Use the timeline slider instead."
                        : ""
                )

                VStack(spacing: 4) {
                    timeline

                    if let first = playback.frames.first, let last = playback.frames.last {
                        timelineLabels(first: first, last: last)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(WeatherTheme.tertiaryText)
                            .accessibilityHidden(true)
                    }
                }
            }

            if isPreparing {
                HStack(spacing: 8) {
                    ProgressView(value: loadingProgress)
                        .tint(WeatherTheme.accent)
                    Text(
                        playback.isPlaying && !playback.isNextFrameReady
                            ? "Buffering…"
                            : "Loading frames \(Int(loadingProgress * 100))%"
                    )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }

            if reduceMotion && playback.frames.count > 1 {
                Text("Reduce Motion is on. Animation stays paused; drag the timeline instead.")
                    .font(.caption2)
                    .foregroundStyle(WeatherTheme.secondaryText)
            }
        }
        .padding(WeatherTheme.cardPadding)
        .weatherSurface()
    }

    private func timelineLabels(first: RadarFrame, last: RadarFrame) -> some View {
        HStack {
            Text(WeatherFormatters.hour(first.timestamp))
            Spacer()
            Text(WeatherFormatters.hour(last.timestamp))
        }
        .overlay {
            if playback.firstForecastIndex != nil,
               let nowIndex = playback.latestObservedIndex,
               playback.frames.count > 1 {
                GeometryReader { proxy in
                    let thumbInset: CGFloat = 14
                    let fraction = CGFloat(nowIndex) / CGFloat(playback.frames.count - 1)
                    let x = thumbInset + fraction * (proxy.size.width - thumbInset * 2)

                    Text("Now")
                        .fontWeight(.semibold)
                        .foregroundStyle(WeatherTheme.accent)
                        .fixedSize()
                        .position(x: x, y: proxy.size.height / 2)
                }
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if playback.frames.count > 1 {
            Slider(
                value: Binding(
                    get: { Double(playback.selectedIndex) },
                    set: { playback.select(index: Int($0.rounded())) }
                ),
                in: 0...Double(playback.frames.count - 1),
                step: 1
            )
            .tint(WeatherTheme.accent)
            .accessibilityLabel("Radar time")
            .accessibilityValue(
                playback.selectedFrame.map { WeatherFormatters.hour($0.timestamp) } ?? ""
            )
        } else {
            Capsule()
                .fill(WeatherTheme.divider)
                .frame(height: 4)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityHidden(true)
        }
    }
}

struct RadarLegend: View {
    /// Sampled from NOAA's GetLegendGraphic for the base reflectivity layer (≈10–70 dBZ).
    private static let stops: [Color] = [
        Color(red: 86 / 255, green: 149 / 255, blue: 193 / 255),
        Color(red: 84 / 255, green: 207 / 255, blue: 170 / 255),
        Color(red: 18 / 255, green: 214 / 255, blue: 29 / 255),
        Color(red: 10 / 255, green: 120 / 255, blue: 13 / 255),
        Color(red: 250 / 255, green: 223 / 255, blue: 0 / 255),
        Color(red: 245 / 255, green: 178 / 255, blue: 20 / 255),
        Color(red: 220 / 255, green: 6 / 255, blue: 6 / 255),
        Color(red: 233 / 255, green: 147 / 255, blue: 253 / 255),
        Color(red: 141 / 255, green: 0 / 255, blue: 236 / 255)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule()
                .fill(LinearGradient(colors: Self.stops, startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)

            HStack {
                Text("Light")
                Spacer()
                Text("Heavy")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(WeatherTheme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Precipitation intensity scale, light to heavy")
    }
}
