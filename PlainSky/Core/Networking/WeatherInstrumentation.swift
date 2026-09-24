import os

enum WeatherInstrumentation {
    static let signposter = OSSignposter(
        subsystem: "com.columbuslabs.plainsky",
        category: "weather.startup"
    )

    static func mark(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    static func measure<Value>(
        _ name: StaticString,
        operation: () throws -> Value
    ) rethrows -> Value {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, interval) }
        return try operation()
    }
}
