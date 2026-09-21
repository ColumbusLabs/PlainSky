import SwiftUI

struct WeatherProviderAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme

    let metadata: WeatherSourceMetadata

    var body: some View {
        if metadata.provider == .weatherKit,
           let legalURL = metadata.attributionLegalURL {
            Link(destination: legalURL) {
                HStack(spacing: 8) {
                    if let markURL = preferredMarkURL {
                        AsyncImage(url: markURL) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFit()

                            default:
                                Text(metadata.attributionServiceName ?? "Apple Weather")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: 116, maxHeight: 18, alignment: .leading)
                    } else {
                        Text(metadata.attributionServiceName ?? "Apple Weather")
                            .font(.caption.weight(.semibold))
                    }

                    Spacer(minLength: 4)

                    Label("Attribution", systemImage: "arrow.up.right")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(WeatherTheme.secondaryText)
            }
            .accessibilityLabel(
                "Apple Weather attribution and legal information"
            )
        }
    }

    private var preferredMarkURL: URL? {
        colorScheme == .dark
            ? metadata.attributionMarkDarkURL
            : metadata.attributionMarkLightURL
    }
}
