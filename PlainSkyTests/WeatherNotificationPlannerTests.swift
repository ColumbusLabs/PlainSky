import XCTest
@testable import PlainSky

final class WeatherNotificationPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let place = WeatherLocation(name: "Franklin", region: "TN", latitude: 35.92, longitude: -86.87)

    private var source: WeatherSourceMetadata {
        WeatherSourceMetadata(
            provider: .nwsForecast,
            productName: "Test",
            sourceName: nil,
            observedAt: nil,
            issuedAt: nil,
            validFrom: nil,
            validTo: nil,
            fetchedAt: now,
            expiresAt: nil,
            validatedAt: now
        )
    }

    private func alert(
        _ id: String,
        event: String,
        expiresIn: TimeInterval = 3600,
        messageType: String? = "Alert",
        references: [String]? = nil
    ) -> WeatherAlert {
        WeatherAlert(
            id: id,
            event: event,
            headline: "\(event) until later",
            severity: .moderate,
            effectiveAt: now.addingTimeInterval(-600),
            expiresAt: now.addingTimeInterval(expiresIn),
            description: "",
            instructions: nil,
            issuingOffice: nil,
            source: source,
            messageType: messageType,
            referencedIDs: references
        )
    }

    private func minutes(_ wet: ClosedRange<Int>?, kind: String = "rain") -> [MinutePrecipitationSample] {
        (0..<60).map { minute in
            let isWet = wet?.contains(minute) ?? false
            return MinutePrecipitationSample(
                date: now.addingTimeInterval(Double(minute) * 60),
                probability: isWet ? 0.8 : 0.05,
                intensity: isWet ? 1.2 : 0,
                kind: isWet ? kind : nil,
                source: source
            )
        }
    }

    func testCategorizesNWSEventNames() {
        XCTAssertEqual(WeatherAlertCategory(event: "Tornado Warning"), .warning)
        XCTAssertEqual(WeatherAlertCategory(event: "Extreme Wind Warning"), .warning)
        XCTAssertEqual(WeatherAlertCategory(event: "Civil Emergency Message"), .warning)
        XCTAssertEqual(WeatherAlertCategory(event: "Evacuation Immediate"), .warning)
        XCTAssertEqual(WeatherAlertCategory(event: "Flood Watch"), .watch)
        XCTAssertEqual(WeatherAlertCategory(event: "Heat Advisory"), .advisory)
        XCTAssertEqual(WeatherAlertCategory(event: "Special Weather Statement"), .statement)
    }

    func testNotifiesEachAlertOnceAndWarningsAreTimeSensitive() {
        var state = WeatherNotifierState()
        let alerts = [alert("a", event: "Tornado Warning"), alert("b", event: "Flood Watch")]

        let first = WeatherNotificationPlanner.plan(
            alerts: alerts, minutePrecipitation: nil, place: place,
            preferences: .init(), state: &state, now: now
        )
        XCTAssertEqual(first.map(\.title), ["Tornado Warning", "Flood Watch"])
        XCTAssertEqual(first.map(\.isTimeSensitive), [true, false])
        XCTAssertEqual(first.first?.subtitle, "Franklin")

        let second = WeatherNotificationPlanner.plan(
            alerts: alerts, minutePrecipitation: nil, place: place,
            preferences: .init(), state: &state, now: now.addingTimeInterval(900)
        )
        XCTAssertTrue(second.isEmpty, "An alert that is still active must not notify again.")
    }

    func testRespectsCategoryToggles() {
        var state = WeatherNotifierState()
        var preferences = WeatherNotificationPreferences()
        preferences.watches = false

        let planned = WeatherNotificationPlanner.plan(
            alerts: [alert("w", event: "Flood Watch"), alert("s", event: "Special Weather Statement")],
            minutePrecipitation: nil, place: place,
            preferences: preferences, state: &state, now: now
        )
        XCTAssertTrue(planned.isEmpty)

        preferences.watches = true
        let enabledLater = WeatherNotificationPlanner.plan(
            alerts: [alert("w", event: "Flood Watch")],
            minutePrecipitation: nil, place: place,
            preferences: preferences, state: &state, now: now
        )
        XCTAssertEqual(enabledLater.count, 1, "A disabled category must not be marked as already sent.")
    }

    func testUpdatesToSentAlertsAndCancellationsStaySilent() {
        var state = WeatherNotifierState()
        _ = WeatherNotificationPlanner.plan(
            alerts: [alert("original", event: "Severe Thunderstorm Warning")],
            minutePrecipitation: nil, place: place, preferences: .init(), state: &state, now: now
        )

        let planned = WeatherNotificationPlanner.plan(
            alerts: [
                alert("update", event: "Severe Thunderstorm Warning", messageType: "Update", references: ["original"]),
                alert("cancel", event: "Flood Watch", messageType: "Cancel")
            ],
            minutePrecipitation: nil, place: place, preferences: .init(), state: &state, now: now
        )
        XCTAssertTrue(planned.isEmpty)
    }

    func testSkipsAlertsPastTheirNWSExpiry() {
        var state = WeatherNotifierState()
        let planned = WeatherNotificationPlanner.plan(
            alerts: [alert("old", event: "Heat Advisory", expiresIn: -60)],
            minutePrecipitation: nil, place: place, preferences: .init(), state: &state, now: now
        )
        XCTAssertTrue(planned.isEmpty)
    }

    func testPrecipitationStartNotifiesWithStartTime() throws {
        var state = WeatherNotifierState()
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let planned = WeatherNotificationPlanner.plan(
            alerts: nil, minutePrecipitation: minutes(10...40), place: place,
            preferences: .init(), state: &state, now: now, timeZone: utc
        )

        let notice = try XCTUnwrap(planned.first)
        let expectedTime = now.addingTimeInterval(600).formatted({
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = utc
            return style
        }())
        XCTAssertEqual(notice.title, "Rain begins around \(expectedTime)")
        XCTAssertEqual(notice.body, "Rain is expected to start in about 10 min.")
        XCTAssertEqual(state.lastPrecipitationNotificationAt, now)

        let again = WeatherNotificationPlanner.plan(
            alerts: nil, minutePrecipitation: minutes(10...40), place: place,
            preferences: .init(), state: &state, now: now.addingTimeInterval(300)
        )
        XCTAssertTrue(again.isEmpty, "Only one precipitation notice per cooldown window.")
    }

    func testNoPrecipitationNoticeWhenAlreadyWetOrOnlyBriefBlip() {
        let state = WeatherNotifierState()
        XCTAssertNil(WeatherNotificationPlanner.precipitationStart(
            samples: minutes(0...30), place: place, state: state, now: now
        ))
        XCTAssertNil(WeatherNotificationPlanner.precipitationStart(
            samples: minutes(20...22), place: place, state: state, now: now
        ))
        XCTAssertNil(WeatherNotificationPlanner.precipitationStart(
            samples: minutes(nil), place: place, state: state, now: now
        ))
    }

    func testSnowUsesProviderPrecipitationType() {
        let notice = WeatherNotificationPlanner.precipitationStart(
            samples: minutes(15...45, kind: "snow"), place: place, state: .init(), now: now
        )
        XCTAssertEqual(notice?.body, "Snow is expected to start in about 15 min.")
    }
}
