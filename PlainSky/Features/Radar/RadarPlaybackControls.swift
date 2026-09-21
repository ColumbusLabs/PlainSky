import SwiftUI

struct RadarPlaybackControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var playback: RadarPlaybackState

    private var playbackDisabled: Bool {
        playback.frames.count < 2 || reduceMotion
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Base reflectivity", systemImage: "cloud.rain")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())

                Spacer()

                if let frame = playback.selectedFrame {
                    Text(frame.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("No radar frame loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                Button {
                    playback.togglePlayback()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(
                            playbackDisabled
                                ? Color.secondary.opacity(0.2)
                                : WeatherTheme.accent,
                            in: Circle()
                        )
                        .foregroundStyle(.white)
                }
                .disabled(playbackDisabled)
                .accessibilityLabel(playback.isPlaying ? "Pause radar" : "Play radar")
                .accessibilityHint(
                    reduceMotion && playback.frames.count > 1
                        ? "Playback is disabled while Reduce Motion is enabled. Use the timeline slider instead."
                        : ""
                )

                if playback.frames.count > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(playback.selectedIndex) },
                            set: { playback.select(index: Int($0.rounded())) }
                        ),
                        in: 0...Double(max(1, playback.frames.count - 1)),
                        step: 1
                    )
                    .tint(WeatherTheme.accent)
                    .accessibilityLabel("Radar frame")
                    .accessibilityValue(
                        "\(playback.selectedIndex + 1) of \(playback.frames.count)"
                    )
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 10, height: 10)
                        }
                        .accessibilityHidden(true)
                }

                Text(playback.frames.isEmpty ? "—" : "\(playback.selectedIndex + 1)/\(playback.frames.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            if reduceMotion && playback.frames.count > 1 {
                Text("Reduce Motion is on. Radar animation stays paused; the timeline remains available.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
