import Foundation

enum NWSParsing {
    // Formatters and the duration pattern are expensive to build and are
    // shared: grid enrichment parses thousands of intervals per refresh.
    // ISO8601DateFormatter and NSRegularExpression are thread safe for parsing
    // and matching.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let durationPattern = try? NSRegularExpression(
        pattern: #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
    )

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractionalFormatter.date(from: string) ?? standardFormatter.date(from: string)
    }

    static func interval(_ string: String) -> (start: Date, end: Date)? {
        let parts = string.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let start = date(parts[0]),
              let duration = duration(parts[1]) else {
            return nil
        }

        return (start, start.addingTimeInterval(duration))
    }

    static func duration(_ string: String) -> TimeInterval? {
        guard let regex = durationPattern,
              let match = regex.firstMatch(
                in: string,
                range: NSRange(string.startIndex..., in: string)
              ) else {
            return nil
        }

        func group(_ index: Int) -> Double {
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: string) else {
                return 0
            }
            return Double(string[swiftRange]) ?? 0
        }

        return group(1) * 86_400
            + group(2) * 3_600
            + group(3) * 60
            + group(4)
    }
}

/// A grid series with its ISO 8601 intervals parsed once, for repeated lookups.
struct NWSParsedGridSeries: Sendable {
    let uom: String?
    private let entries: [(start: Date, end: Date, value: Double?)]

    init(_ series: NWSGridValueSeries) {
        uom = series.uom
        entries = series.values.compactMap { entry in
            NWSParsing.interval(entry.validTime).map { ($0.start, $0.end, entry.value) }
        }
    }

    func value(at date: Date) -> Double? {
        entries.first { $0.start <= date && date < $0.end }?.value
    }
}

extension NWSGridValueSeries {
    func value(at date: Date) -> Double? {
        NWSParsedGridSeries(self).value(at: date)
    }
}
