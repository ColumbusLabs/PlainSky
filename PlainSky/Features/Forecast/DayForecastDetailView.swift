import SwiftUI

struct DayForecastDetailView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHour: HourlyForecastItem?
    @State private var restingOffset: CGFloat?
    @State private var isScrolled = false

    let day: DailyForecastItem

    private let scrollSpace = "dayDetailScroll"

    private var hasDaytime: Bool {
        day.daytimeHigh != nil
    }

    private var matchingHours: [HourlyForecastItem] {
        (store.screenState.hourly.value ?? []).filter {
            Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: day.date)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            WeatherBackdrop(
                style: .forConditions(day.daytimeCondition, isDaytime: hasDaytime)
            )

            ScrollView {
                LazyVStack(spacing: WeatherTheme.sectionSpacing) {
                    hero
                        .padding(.bottom, 10)

                    if hasDaytime {
                        ForecastPeriodCard(
                            title: "Daytime",
                            description: day.daytimeDescription,
                            condition: day.daytimeCondition,
                            isDaytime: true,
                            temperatureLabel: "High",
                            temperature: day.daytimeHigh,
                            precipitationChance: day.daytimePrecipitationChance,
                            wind: day.windDescription,
                            unitSystem: store.unitSystem
                        )
                    }

                    if let nightDescription = day.nighttimeDescription {
                        ForecastPeriodCard(
                            title: "Overnight",
                            description: nightDescription,
                            condition: day.nighttimeCondition ?? .mostlyClear,
                            isDaytime: false,
                            temperatureLabel: "Low",
                            temperature: day.overnightLow,
                            precipitationChance: day.nighttimePrecipitationChance,
                            wind: day.nighttimeWindDescription ?? day.windDescription,
                            unitSystem: store.unitSystem
                        )
                    }

                    if !matchingHours.isEmpty {
                        hoursCard
                    }
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .background(alignment: .top) {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: proxy.frame(in: .named(scrollSpace)).minY
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                DetailNavigationBar(
                    title: "Day Forecast",
                    backTitle: "Forecast",
                    isScrolled: isScrolled,
                    onBack: { dismiss() }
                )
            }
        }
        .coordinateSpace(name: scrollSpace)
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            let resting = restingOffset ?? offset
            if restingOffset == nil {
                restingOffset = offset
            }
            isScrolled = offset < resting - 6
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedHour) { hour in
            HourlyForecastDetailSheet(item: hour)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var hero: some View {
        let dayName = hasDaytime || !Calendar.autoupdatingCurrent.isDateInToday(day.date)
            ? day.date.formatted(.dateTime.weekday(.wide))
            : "Tonight"

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(dayName),\n\(day.date.formatted(.dateTime.month(.wide).day()))")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(day.daytimeCondition.displayName(isDaytime: hasDaytime))
                    .font(.title3.weight(.semibold))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if hasDaytime {
                    heroTemperature(day.daytimeHigh, label: "High")
                }
                heroTemperature(day.overnightLow, label: "Low")
            }
        }
        .foregroundStyle(WeatherTheme.heroText)
        .heroTextShadow()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func heroTemperature(_ value: Double?, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(WeatherFormatters.temperature(value, unitSystem: store.unitSystem))
                .font(.system(size: 36, weight: .semibold))
                .monospacedDigit()

            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WeatherTheme.heroSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var hoursCard: some View {
        WeatherCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Hours")
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                ForEach(matchingHours) { hour in
                    Button {
                        selectedHour = hour
                    } label: {
                        DayHourRow(
                            item: hour,
                            isDaytime: WeatherDaylight.isDaytime(
                                hour.date,
                                solar: store.screenState.solarEvents.value
                            ),
                            unitSystem: store.unitSystem
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DetailNavigationBar: View {
    let title: String
    let backTitle: String
    let isScrolled: Bool
    let onBack: () -> Void

    private var foreground: Color {
        isScrolled ? WeatherTheme.primaryText : WeatherTheme.heroText
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(foreground)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text(backTitle)
                            .font(.body.weight(.medium))
                    }
                    .foregroundStyle(isScrolled ? WeatherTheme.accent : WeatherTheme.heroText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Back to \(backTitle)")

                Spacer()
            }
        }
        .shadow(color: isScrolled ? .clear : WeatherTheme.primaryText.opacity(0.25), radius: 6, y: 1)
        .padding(.horizontal, WeatherTheme.horizontalPadding)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(WeatherTheme.divider)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
                .opacity(isScrolled ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.18), value: isScrolled)
    }
}

private struct ForecastPeriodCard: View {
    let title: String
    let description: String
    let condition: WeatherCondition
    let isDaytime: Bool
    let temperatureLabel: String
    let temperature: Double?
    let precipitationChance: Double?
    let wind: String?
    let unitSystem: WeatherUnitSystem

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(WeatherTheme.primaryText)

                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(WeatherTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    ConditionIcon(condition: condition, isDaytime: isDaytime, size: 44)
                }

                Divider()
                    .overlay(WeatherTheme.divider)

                HStack(spacing: 0) {
                    ForecastFact(
                        label: temperatureLabel,
                        value: WeatherFormatters.temperature(temperature, unitSystem: unitSystem),
                        icon: nil
                    )

                    factDivider

                    ForecastFact(
                        label: "Precipitation",
                        value: WeatherFormatters.percent(precipitationChance),
                        icon: "drop.fill"
                    )

                    if let wind {
                        factDivider

                        ForecastFact(label: "Wind", value: wind, icon: "wind")
                            .layoutPriority(1)
                    }
                }
            }
        }
    }

    private var factDivider: some View {
        Rectangle()
            .fill(WeatherTheme.divider)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 10)
    }
}

private struct ForecastFact: View {
    let label: String
    let value: String
    let icon: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(WeatherTheme.secondaryText)

            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(WeatherTheme.accent)
                }

                Text(value)
                    .font(.headline)
                    .foregroundStyle(WeatherTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct DayHourRow: View {
    let item: HourlyForecastItem
    let isDaytime: Bool
    let unitSystem: WeatherUnitSystem

    var body: some View {
        HStack(spacing: 12) {
            Text(WeatherFormatters.hourLabel(item.date))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WeatherTheme.primaryText)
                .frame(width: 56, alignment: .leading)

            ConditionIcon(condition: item.condition, isDaytime: isDaytime, size: 20)
                .frame(width: 28)

            Text(WeatherFormatters.temperature(item.temperature, unitSystem: unitSystem))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(WeatherTheme.primaryText)
                .frame(width: 44, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(WeatherTheme.accent)
                Text(WeatherFormatters.percent(item.precipitationChance))
                    .monospacedDigit()
                    .foregroundStyle(WeatherTheme.secondaryText)
            }
            .font(.caption.weight(.medium))

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeatherTheme.tertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .weatherInsetSurface(cornerRadius: 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens hour details")
    }
}
