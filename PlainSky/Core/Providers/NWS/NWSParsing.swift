import Foundation

enum NWSParsing {
    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
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
        let pattern = #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
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

extension NWSGridValueSeries {
    func value(at date: Date) -> Double? {
        for entry in values {
            guard let interval = NWSParsing.interval(entry.validTime),
                  interval.start <= date,
                  date < interval.end else {
                continue
            }
            return entry.value
        }

        return nil
    }
}
