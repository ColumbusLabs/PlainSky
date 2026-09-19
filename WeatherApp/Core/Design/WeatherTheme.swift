import SwiftUI

enum WeatherTheme {
    static let accent = Color(red: 0.31, green: 0.72, blue: 0.98)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.70)
    static let tertiaryText = Color.white.opacity(0.48)
    static let cardFill = Color.white.opacity(0.095)
    static let cardStroke = Color.white.opacity(0.12)
    static let divider = Color.white.opacity(0.10)

    static let horizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let smallRadius: CGFloat = 16

    static let clearTop = Color(red: 0.06, green: 0.20, blue: 0.38)
    static let clearBottom = Color(red: 0.02, green: 0.06, blue: 0.13)
    static let rainTop = Color(red: 0.09, green: 0.16, blue: 0.24)
    static let rainBottom = Color(red: 0.03, green: 0.06, blue: 0.10)
}

struct WeatherCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: WeatherTheme.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.72))
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
