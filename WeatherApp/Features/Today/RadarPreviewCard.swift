import SwiftUI

struct RadarPreviewCard: View {
    let location: WeatherLocation

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Radar")

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.12, blue: 0.18),
                                    Color(red: 0.08, green: 0.20, blue: 0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RadarGlyph()
                        .padding(24)

                    VStack {
                        Spacer()

                        HStack {
                            Label(location.name, systemImage: "location.fill")
                                .font(.caption.weight(.semibold))

                            Spacer()

                            Label("NOAA", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(14)
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("Radar preview for \(location.displayName)")
            }
        }
    }
}

private struct RadarGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                ForEach([0.32, 0.58, 0.84], id: \.self) { scale in
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        .frame(width: size * scale, height: size * scale)
                }

                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

                Circle()
                    .fill(WeatherTheme.accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: WeatherTheme.accent.opacity(0.8), radius: 8)

                Image(systemName: "cloud.rain.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 34))
                    .offset(x: size * 0.23, y: -size * 0.18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
