import SwiftUI

enum WeatherTheme {
    static let accent = Color(red: 0.20, green: 0.58, blue: 0.96)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.72)
    static let cardFill = Color.primary.opacity(0.025)
    static let cardStroke = Color.primary.opacity(0.10)
    static let divider = Color.primary.opacity(0.09)

    static let horizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let smallRadius: CGFloat = 16

    static let clearTop = Color(red: 0.06, green: 0.20, blue: 0.38)
    static let clearBottom = Color(red: 0.02, green: 0.06, blue: 0.13)
    static let rainTop = Color(red: 0.09, green: 0.16, blue: 0.24)
    static let rainBottom = Color(red: 0.03, green: 0.06, blue: 0.10)
}

struct WeatherCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: WeatherTheme.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: WeatherTheme.cardRadius, style: .continuous)
                            .fill(WeatherTheme.cardFill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: WeatherTheme.cardRadius, style: .continuous)
                            .stroke(WeatherTheme.cardStroke, lineWidth: 1)
                    }
            }
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(WeatherTheme.secondaryText)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeatherTheme.accent)
            }
        }
    }
}
