import SwiftUI

struct WeatherSourceFooter: View {
    let primary: WeatherSourceMetadata
    let attributionCandidates: [WeatherSourceMetadata]

    init(primary: WeatherSourceMetadata, attributionCandidates: [WeatherSourceMetadata]) {
        self.primary = primary
        self.attributionCandidates = attributionCandidates
    }

    init(snapshot: WeatherSnapshot) {
        self.init(
            primary: snapshot.current.source,
            attributionCandidates: [
                snapshot.current.source,
                snapshot.minutePrecipitation.first?.source,
                snapshot.solar?.source,
                snapshot.hourly.first?.source,
                snapshot.daily.first?.source
            ].compactMap { $0 }
        )
    }

    /// Apple requires its Weather mark and legal link wherever WeatherKit data is shown.
    private var weatherKitSource: WeatherSourceMetadata? {
        ([primary] + attributionCandidates).first {
            $0.provider == .weatherKit && $0.attributionLegalURL != nil
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            NavigationLink {
                DiagnosticsView()
            } label: {
                HStack(spacing: 6) {
                    SourceFreshnessView(metadata: primary)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WeatherTheme.tertiaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(WeatherTheme.insetFill)
                        .overlay(Capsule().strokeBorder(WeatherTheme.insetStroke, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens data sources and freshness details")

            if let weatherKitSource {
                WeatherProviderAttributionView(metadata: weatherKitSource)
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}
