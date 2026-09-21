import XCTest
@testable import PlainSky

final class NWSParsingTests: XCTestCase {
    func testParsesDateAndGridInterval() throws {
        let date = try XCTUnwrap(NWSParsing.date("2026-09-19T18:00:00-04:00"))
        let interval = try XCTUnwrap(
            NWSParsing.interval("2026-09-19T18:00:00-04:00/PT3H")
        )

        XCTAssertEqual(interval.start, date)
        XCTAssertEqual(interval.end.timeIntervalSince(interval.start), 10_800, accuracy: 0.1)
    }

    func testParsesLongDuration() throws {
        XCTAssertEqual(
            try XCTUnwrap(NWSParsing.duration("P7DT17H")),
            7 * 86_400 + 17 * 3_600,
            accuracy: 0.1
        )
    }

    func testGridSeriesReturnsValueForCoveredHour() throws {
        let series = NWSGridValueSeries(
            uom: "wmoUnit:degC",
            values: [
                NWSGridValue(
                    validTime: "2026-09-19T18:00:00-04:00/PT3H",
                    value: 20
                )
            ]
        )

        let target = try XCTUnwrap(NWSParsing.date("2026-09-19T20:00:00-04:00"))
        XCTAssertEqual(series.value(at: target), 20)
    }

    func testUnitConversionsUseCanonicalUSBasis() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                NWSUnitConverter.temperatureFahrenheit(
                    20,
                    unitCode: "wmoUnit:degC"
                )
            ),
            68,
            accuracy: 0.001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                NWSUnitConverter.speedMPH(
                    10,
                    unitCode: "wmoUnit:km_h-1"
                )
            ),
            6.2137,
            accuracy: 0.001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                NWSUnitConverter.pressureMillibars(
                    NWSQuantitativeValue(unitCode: "wmoUnit:Pa", value: 101_325)
                )
            ),
            1_013.25,
            accuracy: 0.001
        )
    }

    func testLegacyWindRangeIsNotCollapsedIntoFakeNumericValue() {
        XCTAssertNil(NWSUnitConverter.exactLegacySpeedMPH("7 to 10 mph"))
        XCTAssertEqual(
            NWSUnitConverter.exactLegacySpeedMPH("7 mph"),
            7
        )
    }

    func testConditionMapping() {
        XCTAssertEqual(
            NWSConditionMapper.condition(from: "Chance Thunderstorms"),
            .thunderstorm
        )
        XCTAssertEqual(
            NWSConditionMapper.condition(from: "Partly Cloudy"),
            .partlyCloudy
        )
        XCTAssertEqual(
            NWSConditionMapper.condition(from: "Fair"),
            .clear
        )
    }
}
