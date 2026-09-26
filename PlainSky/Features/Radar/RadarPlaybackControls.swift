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

    private var isLatestObserved: Bool {
        playback.selectedIndex == playback.latestObservedIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                playButton

                VStack(alignment: .leading, spacing: 1) {
                    Text(playback.selectedFrame.map { WeatherFormatters.hour($0.timestamp) } ?? "—")
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(WeatherTheme.primaryText)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: playback.selectedIndex)

                    Text(ageLabel)
                        .font(.footnote)
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 8)

                statusChip
            }

            VStack(spacing: 6) {
                RadarTimeline(playback: playback)

                if let first = playback.frames.first, let last = playback.frames.last {
                    timelineLabels(first: first, last: last)
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(WeatherTheme.tertiaryText)
                        .accessibilityHidden(true)
                }
            }

            RadarLegend()

            if reduceMotion && playback.frames.count > 1 {
                Text("Reduce Motion is on. Animation stays paused; drag the timeline instead.")
                    .font(.caption2)
                    .foregroundStyle(WeatherTheme.secondaryText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .radarGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var playButton: some View {
        Button {
            playback.togglePlayback()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 48, height: 48)
                .background(
                    playbackDisabled
                        ? AnyShapeStyle(WeatherTheme.tertiaryText)
                        : AnyShapeStyle(WeatherTheme.accent.gradient),
                    in: Circle()
                )
                .shadow(color: WeatherTheme.accent.opacity(playbackDisabled ? 0 : 0.35), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(playbackDisabled)
        .accessibilityLabel(playback.isPlaying ? "Pause radar" : "Play radar")
        .accessibilityHint(
            reduceMotion && playback.frames.count > 1
                ? "Playback is disabled while Reduce Motion is enabled. Use the timeline instead."
                : ""
        )
    }

    @ViewBuilder
    private var statusChip: some View {
        Group {
            if isPreparing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(WeatherTheme.secondaryText)
                    Text(
                        playback.isPlaying && !playback.isNextFrameReady
                            ? "Buffering"
                            : "Loading \(Int(loadingProgress * 100))%"
                    )
                    .monospacedDigit()
                }
                .foregroundStyle(WeatherTheme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(WeatherTheme.divider, in: Capsule())
            } else if isShowingForecast {
                chipLabel("Forecast", dot: Color(red: 0.55, green: 0.36, blue: 0.96))
            } else if isLatestObserved {
                chipLabel("Live", dot: Color(red: 0.2, green: 0.78, blue: 0.35))
            } else if playback.selectedFrame != nil {
                chipLabel("Past", dot: WeatherTheme.tertiaryText)
            }
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    private func chipLabel(_ title: String, dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(WeatherTheme.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(WeatherTheme.divider, in: Capsule())
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
                    let fraction = CGFloat(nowIndex) / CGFloat(playback.frames.count - 1)
                    let x = RadarTimeline.inset + fraction * (proxy.size.width - RadarTimeline.inset * 2)

                    Text("Now")
                        .fontWeight(.semibold)
                        .foregroundStyle(WeatherTheme.accent)
                        .fixedSize()
                        .position(x: x, y: proxy.size.height / 2)
                }
            }
        }
    }
}

/// Segmented scrubber: one tick per frame. Played frames fill with the accent,
/// forecast frames use a violet tint, and frames still downloading stay faint.
private struct RadarTimeline: View {
    static let inset: CGFloat = 10

    @Bindable var playback: RadarPlaybackState
    @State private var isScrubbing = false

    private static let forecastTint = Color(red: 0.55, green: 0.36, blue: 0.96)

    var body: some View {
        GeometryReader { proxy in
            let count = playback.frames.count
            let width = proxy.size.width - Self.inset * 2
            let thumbX = count > 1
                ? Self.inset + CGFloat(playback.selectedIndex) / CGFloat(count - 1) * width
                : Self.inset

            ZStack(alignment: .leading) {
                if count > 1 {
                    HStack(spacing: 3) {
                        ForEach(Array(playback.frames.enumerated()), id: \.element.id) { index, frame in
                            Capsule()
                                .fill(tickColor(index: index, frame: frame))
                                .frame(height: 6)
                        }
                    }
                    .padding(.horizontal, Self.inset - 2)
                    .animation(.easeOut(duration: 0.2), value: playback.readyFrameIDs)

                    if let nowIndex = playback.latestObservedIndex, playback.firstForecastIndex != nil {
                        Capsule()
                            .fill(WeatherTheme.accent)
                            .frame(width: 2, height: 18)
                            .position(
                                x: Self.inset + CGFloat(nowIndex) / CGFloat(count - 1) * width,
                                y: proxy.size.height / 2
                            )
                    }

                    Circle()
                        .fill(.white)
                        .frame(width: isScrubbing ? 26 : 22, height: isScrubbing ? 26 : 22)
                        .overlay(Circle().strokeBorder(WeatherTheme.accent, lineWidth: 3))
                        .shadow(color: WeatherTheme.primaryText.opacity(0.25), radius: 4, y: 1)
                        .position(x: thumbX, y: proxy.size.height / 2)
                        .animation(.snappy(duration: 0.18), value: isScrubbing)
                } else {
                    Capsule()
                        .fill(WeatherTheme.divider)
                        .frame(height: 6)
                        .padding(.horizontal, Self.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard count > 1 else { return }
                        if !isScrubbing {
                            isScrubbing = true
                            playback.isPlaying = false
                        }
                        let fraction = min(max((value.location.x - Self.inset) / width, 0), 1)
                        playback.select(index: Int((fraction * CGFloat(count - 1)).rounded()))
                    }
                    .onEnded { _ in isScrubbing = false }
            )
        }
        .frame(height: 30)
        .sensoryFeedback(.selection, trigger: playback.selectedIndex) { _, _ in isScrubbing }
        .accessibilityElement()
        .accessibilityLabel("Radar time")
        .accessibilityValue(playback.selectedFrame.map { WeatherFormatters.hour($0.timestamp) } ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.select(index: playback.selectedIndex + 1)
            case .decrement: playback.select(index: playback.selectedIndex - 1)
            @unknown default: break
            }
        }
    }

    private func tickColor(index: Int, frame: RadarFrame) -> Color {
        let isReady = playback.readyFrameIDs.contains(frame.id)
        let base = frame.kind == .forecast ? Self.forecastTint : WeatherTheme.accent

        if index <= playback.selectedIndex {
            return base.opacity(isReady ? 1 : 0.45)
        }
        return base.opacity(isReady ? 0.28 : 0.1)
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
        HStack(spacing: 10) {
            Text("Light")

            Capsule()
                .fill(LinearGradient(colors: Self.stops, startPoint: .leading, endPoint: .trailing))
                .frame(height: 5)

            Text("Heavy")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(WeatherTheme.secondaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Precipitation intensity scale, light to heavy")
    }
}
