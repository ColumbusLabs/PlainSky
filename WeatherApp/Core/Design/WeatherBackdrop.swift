import SwiftUI

enum WeatherBackdropStyle {
    case clear
    case cloudy
    case rain
    case night
}

struct WeatherBackdrop: View {
    var style: WeatherBackdropStyle = .clear

    private var gradient: LinearGradient {
        let colors: [Color]

        switch style {
        case .clear:
            colors = [WeatherTheme.clearTop, WeatherTheme.clearBottom]
        case .cloudy:
            colors = [
                Color(red: 0.16, green: 0.24, blue: 0.32),
                Color(red: 0.04, green: 0.08, blue: 0.13)
            ]
        case .rain:
            colors = [WeatherTheme.rainTop, WeatherTheme.rainBottom]
        case .night:
            colors = [
                Color(red: 0.04, green: 0.08, blue: 0.19),
                Color(red: 0.01, green: 0.02, blue: 0.07)
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                gradient

                Circle()
                    .fill(WeatherTheme.accent.opacity(0.13))
                    .frame(width: proxy.size.width * 1.2)
                    .blur(radius: 70)
                    .offset(
                        x: proxy.size.width * 0.35,
                        y: -proxy.size.height * 0.35
                    )

                Circle()
                    .fill(Color.white.opacity(0.05))
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
