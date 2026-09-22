import SwiftUI

enum WeatherTheme {
    static let accent = Color(red: 0.16, green: 0.49, blue: 0.93)
    static let primaryText = Color(red: 0.06, green: 0.16, blue: 0.32)
    static let secondaryText = Color(red: 0.29, green: 0.38, blue: 0.52)
    static let tertiaryText = Color(red: 0.29, green: 0.38, blue: 0.52).opacity(0.72)
    static let heroText = Color.white
    static let heroSecondaryText = Color.white.opacity(0.92)
    static let cardFill = Color.white.opacity(0.52)
    static let cardStroke = Color.white.opacity(0.75)
    static let insetFill = Color.white.opacity(0.5)
    static let insetStroke = Color.white.opacity(0.65)
    static let divider = primaryText.opacity(0.09)
    static let shadow = primaryText.opacity(0.08)

    static let horizontalPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let smallRadius: CGFloat = 14
}

extension View {
    func weatherSurface(cornerRadius: CGFloat = WeatherTheme.cardRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(WeatherTheme.cardFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(WeatherTheme.cardStroke, lineWidth: 1)
                }
                .shadow(color: WeatherTheme.shadow, radius: 14, y: 6)
        }
    }

    func weatherInsetSurface(cornerRadius: CGFloat = WeatherTheme.smallRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(WeatherTheme.insetFill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(WeatherTheme.insetStroke, lineWidth: 1)
                }
        }
    }

    /// Keeps white hero text legible over the brightest parts of the sky image.
    func heroTextShadow() -> some View {
        shadow(color: WeatherTheme.primaryText.opacity(0.28), radius: 6, y: 1)
    }
}

struct WeatherCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(
        padding: CGFloat = WeatherTheme.cardPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .weatherSurface()
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(WeatherTheme.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WeatherTheme.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
    }
}
