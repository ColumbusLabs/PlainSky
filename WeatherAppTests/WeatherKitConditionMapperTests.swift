import XCTest
@testable import WeatherApp

final class WeatherKitConditionMapperTests: XCTestCase {
    func testMapsCommonAppleWeatherSymbols() {
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "sun.max.fill"),
            .clear
        )
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "cloud.sun.fill"),
            .partlyCloudy
        )
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "cloud.rain.fill"),
            .rain
        )
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "cloud.heavyrain.fill"),
            .heavyRain
        )
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "cloud.bolt.rain.fill"),
            .thunderstorm
        )
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "cloud.snow.fill"),
            .snow
        )
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "cloud.fog.fill"),
            .fog
        )
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "wind"),
            .windy
        )
    }

    func testUnknownSymbolRemainsUnknown() {
        XCTAssertEqual(
            WeatherKitConditionMapper.condition(symbolName: "sparkles"),
            .unknown
        )
    }
}
