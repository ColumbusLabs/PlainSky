import SwiftUI

struct ConditionIcon: View {
    let condition: WeatherCondition
    var isDaytime = true
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: condition.symbolName(isDaytime: isDaytime))
            .symbolRenderingMode(.multicolor)
            .foregroundStyle(WeatherTheme.accent)
            .font(.system(size: size, weight: .medium))
            .accessibilityHidden(true)
    }
}
