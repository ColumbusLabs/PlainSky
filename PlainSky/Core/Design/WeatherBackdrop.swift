import SwiftUI

enum WeatherBackdropStyle {
    case clear
    case cloudy
    case rain
    case night
    /// Soft sky gradient for settings-style screens where text sits directly on the backdrop.
    case calm

    static func forConditions(
        _ condition: WeatherCondition,
        isDaytime: Bool
    ) -> WeatherBackdropStyle {
        guard isDaytime else { return .night }

        switch condition {
        case .rain, .heavyRain, .thunderstorm:
            return .rain
        case .cloudy, .fog, .snow:
            return .cloudy
        case .clear, .mostlyClear, .partlyCloudy, .windy, .unknown:
            return .clear
        }
    }

    static func current(
        for snapshot: WeatherSnapshot,
        at date: Date = Date()
    ) -> WeatherBackdropStyle {
        forConditions(
            snapshot.current.condition,
            isDaytime: WeatherDaylight.isDaytime(date, solar: snapshot.solar)
        )
    }

    static func current(
        for state: WeatherScreenState,
        at date: Date = Date()
    ) -> WeatherBackdropStyle {
        guard let current = state.current.value else { return .calm }
        return forConditions(
            current.condition,
            isDaytime: WeatherDaylight.isDaytime(date, solar: state.solarEvents.value)
        )
    }

    fileprivate var imageName: String? {
        switch self {
        case .clear, .cloudy, .rain: "SkyDay"
        case .night: "SkyNight"
        case .calm: nil
        }
    }

    fileprivate var saturation: Double {
        switch self {
        case .clear, .night, .calm: 1
        case .cloudy: 0.35
        case .rain: 0.2
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .clear, .night, .calm: .clear
        case .cloudy: Color(red: 0.55, green: 0.62, blue: 0.70).opacity(0.28)
        case .rain: Color(red: 0.28, green: 0.36, blue: 0.47).opacity(0.38)
        }
    }
}

struct WeatherBackdrop: View {
    var style: WeatherBackdropStyle = .calm

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.80, green: 0.90, blue: 0.99),
                    Color(red: 0.93, green: 0.97, blue: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let imageName = style.imageName {
                Color.clear
                    .overlay(alignment: .top) {
                        Image(imageName)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .saturation(style.saturation)
                    .overlay(style.tint)

                // Deepens the sky behind the header so white text stays
                // readable over bright clouds without hiding the photo.
                LinearGradient(
                    stops: [
                        .init(color: WeatherTheme.primaryText.opacity(0.32), location: 0),
                        .init(color: WeatherTheme.primaryText.opacity(0.26), location: 0.3),
                        .init(color: WeatherTheme.primaryText.opacity(0.12), location: 0.45),
                        .init(color: .clear, location: 0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
