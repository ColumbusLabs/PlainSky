import SwiftUI
import WidgetKit

@main
struct PlainSkyWidgetBundle: WidgetBundle {
    var body: some Widget {
        ConditionsWidget()
    }
}

struct ConditionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PlainSkyShared.conditionsWidgetKind, provider: ConditionsProvider()) { entry in
            ConditionsWidgetView(entry: entry)
                .containerBackground(for: .widget) { ConditionsWidgetView.background }
        }
        .configurationDisplayName("Conditions")
        .description("Current temperature, today's high and low, and the next three hours.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct ConditionsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetWeatherSnapshot?
    let unitSystem: WeatherUnitSystem
}

struct ConditionsProvider: TimelineProvider {
    /// Cached data younger than this is shown without contacting NWS.
    private static let reuseAge: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> ConditionsEntry {
        ConditionsEntry(date: Date(), snapshot: .sample, unitSystem: .us)
    }

    func getSnapshot(in context: Context, completion: @escaping (ConditionsEntry) -> Void) {
        let settings = SharedWeatherSettings()
        completion(ConditionsEntry(
            date: Date(),
            snapshot: settings.widgetSnapshot ?? (context.isPreview ? .sample : nil),
            unitSystem: settings.unitSystem
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ConditionsEntry>) -> Void) {
        Task { @MainActor in
            let settings = SharedWeatherSettings()
            let snapshot = await Self.loadSnapshot(settings: settings)
            let now = Date()

            // One entry per hour boundary so the three hourly columns advance
            // even between data refreshes.
            var dates = [now]
            if let nextHour = Calendar.current.nextDate(
                after: now,
                matching: DateComponents(minute: 0),
                matchingPolicy: .nextTime
            ) {
                dates += (0..<4).map { nextHour.addingTimeInterval(Double($0) * 3600) }
            }

            let entries = dates.map {
                ConditionsEntry(date: $0, snapshot: snapshot, unitSystem: settings.unitSystem)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    @MainActor
    private static func loadSnapshot(settings: SharedWeatherSettings) async -> WidgetWeatherSnapshot? {
        let cached = settings.widgetSnapshot
        guard let place = settings.homePlace else { return cached }

        if let cached,
           WeatherRequestLocationKey(cached.location) == WeatherRequestLocationKey(place),
           Date().timeIntervalSince(cached.asOf) < reuseAge {
            return cached
        }

        let repository = AppEnvironment.makeLiveRepository(includeWeatherKit: false)
        let fetched: WeatherSnapshot? = await withTaskGroup(of: WeatherSnapshot?.self) { group in
            group.addTask { try? await repository.load(location: place) }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let fetched,
              let fresh = WidgetWeatherSnapshot(
                state: WeatherScreenState(preview: fetched),
                asOf: fetched.fetchedAt
              ) else {
            return cached
        }

        settings.widgetSnapshot = fresh
        return fresh
    }
}

struct ConditionsWidgetView: View {
    let entry: ConditionsEntry

    static let background = LinearGradient(
        stops: [
            .init(color: Color(red: 0 / 255, green: 112 / 255, blue: 147 / 255), location: 0),
            .init(color: Color(red: 0 / 255, green: 112 / 255, blue: 147 / 255), location: 0.52),
            .init(color: Color(red: 62 / 255, green: 151 / 255, blue: 180 / 255), location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("PlainSky")
                    .font(.system(size: 15, weight: .medium))
                Text("Open the app to load weather.")
                    .font(.system(size: 13))
                    .opacity(0.8)
                Spacer()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(15)
        }
    }

    private func content(_ snapshot: WidgetWeatherSnapshot) -> some View {
        let hours = snapshot.upcomingHours(after: entry.date)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.location.name)
                    .font(.system(size: 15))

                Text(currentLine(snapshot))
                    .font(.system(size: 18))
                    .minimumScaleFactor(0.75)

                Text(highLowLine(snapshot))
                    .font(.system(size: 16))
            }
            .lineLimit(1)
            .padding(.horizontal, 15)

            Spacer(minLength: 6)

            HStack(spacing: 0) {
                ForEach(hours, id: \.date) { hour in
                    VStack(spacing: 5) {
                        Text(Self.compactHour(hour.date))
                            .font(.system(size: 15))
                        Text(temperature(hour.temperature))
                            .font(.system(size: 18))
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: 6)

            Text("As of \(Self.compactTime(snapshot.asOf))")
                .font(.system(size: 12))
                .opacity(0.75)
                .padding(.horizontal, 15)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 13)
        .padding(.bottom, 13)
    }

    private func currentLine(_ snapshot: WidgetWeatherSnapshot) -> String {
        let temp = snapshot.temperature.map(temperature) ?? "—"
        guard let description = snapshot.conditionDescription, !description.isEmpty else { return temp }
        return "\(temp) \(description)"
    }

    private func highLowLine(_ snapshot: WidgetWeatherSnapshot) -> String {
        switch (snapshot.high, snapshot.low) {
        case let (high?, low?): "H \(temperature(high)) • L \(temperature(low))"
        case let (high?, nil): "H \(temperature(high))"
        case let (nil, low?): "L \(temperature(low))"
        case (nil, nil): ""
        }
    }

    private func temperature(_ fahrenheit: Double) -> String {
        WeatherFormatters.temperature(fahrenheit, unitSystem: entry.unitSystem)
    }

    /// "1p", "12a"
    static func compactHour(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "a" : "p")"
    }

    /// "12:30p"
    static func compactTime(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute))\(hour < 12 ? "a" : "p")"
    }
}

private extension WidgetWeatherSnapshot {
    static var sample: WidgetWeatherSnapshot {
        let now = Date()
        let start = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        return WidgetWeatherSnapshot(
            location: WeatherLocation(name: "Franklin", region: "", latitude: 35.92, longitude: -86.87),
            temperature: 69,
            conditionDescription: "Sunny",
            condition: .clear,
            high: 75,
            low: 44,
            hours: (1...3).map { .init(date: start.addingTimeInterval(Double($0) * 3600), temperature: 69 + Double($0)) },
            asOf: now
        )
    }
}

#Preview(as: .systemSmall) {
    ConditionsWidget()
} timeline: {
    ConditionsEntry(date: Date(), snapshot: .sample, unitSystem: .us)
}
