import SwiftUI

struct RadarPlaybackControls: View {
    @Bindable var playback: RadarPlaybackState

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Menu {
                    Picker("Radar layer", selection: $playback.layer) {
                        ForEach(RadarLayer.allCases) { layer in
                            Label(layer.title, systemImage: layer.symbol)
                                .tag(layer)
                        }
                    }
                } label: {
                    Label(playback.layer.title, systemImage: "square.3.layers.3d")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }

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
                            playback.frames.count > 1 ? WeatherTheme.accent : Color.secondary.opacity(0.2),
                            in: Circle()
                        )
                        .foregroundStyle(.white)
                }
                .disabled(playback.frames.count < 2)
                .accessibilityLabel(playback.isPlaying ? "Pause radar" : "Play radar")

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
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
