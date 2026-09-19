import Foundation

enum RadarTimeParser {
    static func frameTimes(from capabilitiesData: Data) throws -> [Date] {
        let delegate = WMSCapabilitiesTimeDelegate()
        let parser = XMLParser(data: capabilitiesData)
        parser.delegate = delegate

        guard parser.parse() else {
            throw RadarProviderError.invalidCapabilities
        }

        let timestamps = delegate.timeValues
            .flatMap(expandTimeExpression)
            .reduce(into: Set<Date>()) { result, date in
                result.insert(date)
            }
            .sorted()

        guard !timestamps.isEmpty else {
            throw RadarProviderError.noFrameTimes
        }

        return timestamps
    }

    static func expandTimeExpression(_ expression: String) -> [Date] {
        expression
            .split(separator: ",")
            .flatMap { token in
                expandToken(String(token))
            }
    }

    private static func expandToken(_ raw: String) -> [Date] {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return [] }

        let components = token.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)

        if components.count == 1 {
            return date(components[0]).map { [$0] } ?? []
        }

        guard components.count == 3,
              let start = date(components[0]),
              let end = date(components[1]),
              let step = duration(components[2]),
              step > 0 else {
            return []
        }

        var dates: [Date] = []
        var current = start
        var count = 0

        while current <= end && count < 240 {
            dates.append(current)
            current = current.addingTimeInterval(step)
            count += 1
        }

        return dates
    }

    private static func date(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }

    private static func duration(_ string: String) -> TimeInterval? {
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

private final class WMSCapabilitiesTimeDelegate: NSObject, XMLParserDelegate {
    private(set) var timeValues: [String] = []

    private var collectingTime = false
    private var buffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard localName == "Dimension" || localName == "Extent",
              attributeDict["name"]?.lowercased() == "time" else {
            return
        }

        collectingTime = true
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard collectingTime else { return }
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard collectingTime,
              localName == "Dimension" || localName == "Extent" else {
            return
        }

        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            timeValues.append(value)
        }

        collectingTime = false
        buffer = ""
    }
}

enum RadarProviderError: LocalizedError, Equatable {
    case unsupportedRegion
    case invalidCapabilities
    case noFrameTimes

    var errorDescription: String? {
        switch self {
        case .unsupportedRegion:
            "NOAA composite radar is not yet configured for this location."
        case .invalidCapabilities:
            "NOAA radar capabilities could not be read."
        case .noFrameTimes:
            "NOAA radar did not advertise any current scan times."
        }
    }
}
