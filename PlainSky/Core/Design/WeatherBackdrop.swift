import SwiftUI

enum WeatherBackdropStyle {
    case clear
    case cloudy
    case rain
    case night
}

struct WeatherBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var style: WeatherBackdropStyle = .clear

    private var gradient: LinearGradient {
        let colors = colorScheme == .dark ? darkColors : lightColors

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var darkColors: [Color] {
        switch style {
        case .clear:
            [WeatherTheme.clearTop, WeatherTheme.clearBottom]
        case .cloudy:
            [
                Color(red: 0.16, green: 0.24, blue: 0.32),
                Color(red: 0.04, green: 0.08, blue: 0.13)
            ]
        case .rain:
            [WeatherTheme.rainTop, WeatherTheme.rainBottom]
        case .night:
            [
                Color(red: 0.04, green: 0.08, blue: 0.19),
                Color(red: 0.01, green: 0.02, blue: 0.07)
            ]
        }
    }

    private var lightColors: [Color] {
        switch style {
        case .clear:
            [
                Color(red: 0.78, green: 0.90, blue: 0.99),
                Color(red: 0.94, green: 0.97, blue: 1.00)
            ]
        case .cloudy:
            [
                Color(red: 0.80, green: 0.86, blue: 0.91),
                Color(red: 0.94, green: 0.96, blue: 0.98)
            ]
        case .rain:
            [
                Color(red: 0.70, green: 0.80, blue: 0.87),
                Color(red: 0.91, green: 0.94, blue: 0.97)
            ]
        case .night:
            [
                Color(red: 0.83, green: 0.88, blue: 0.96),
                Color(red: 0.95, green: 0.97, blue: 1.00)
            ]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                gradient

                Circle()
                    .fill(WeatherTheme.accent.opacity(colorScheme == .dark ? 0.13 : 0.10))
                    .frame(width: proxy.size.width * 1.2)
                    .blur(radius: 70)
                    .offset(
                        x: proxy.size.width * 0.35,
                        y: -proxy.size.height * 0.35
                    )

                Circle()
                    .fill(
                        (colorScheme == .dark ? Color.white : Color.blue)
                            .opacity(colorScheme == .dark ? 0.05 : 0.035)
                    )
                    .frame(width: proxy.size.width * 0.8)
                    .blur(radius: 80)
                    .offset(
                        x: -proxy.size.width * 0.35,
                        y: proxy.size.height * 0.28
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
