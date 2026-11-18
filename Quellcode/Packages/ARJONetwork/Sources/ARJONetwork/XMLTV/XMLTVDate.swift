import Foundation

/// XMLTV-Zeitangaben: `20261024183000 +0200` (Sekunden und Offset optional, ohne Offset gilt UTC).
/// Rechnet ohne Calendar, weil EPG-Dateien Hunderttausende Sendungen enthalten.
enum XMLTVDate {
    static func parse(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespaces)
        let digits = value.prefix { $0.isASCII && $0.isNumber }
        guard digits.count >= 12, digits.count <= 14 else { return nil }
        let numbers = digits.compactMap { $0.wholeNumberValue }

        func component(_ range: Range<Int>) -> Int {
            numbers[range.clamped(to: 0..<numbers.count)].reduce(0) { $0 * 10 + $1 }
        }
        let year = component(0..<4), month = component(4..<6), day = component(6..<8)
        let hour = component(8..<10), minute = component(10..<12), second = component(12..<14)
        guard (1...12).contains(month), (1...31).contains(day),
              hour < 24, minute < 60, second < 61
        else { return nil }

        var offset = 0
        let rest = value.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty {
            guard let parsed = parseOffset(rest) else { return nil }
            offset = parsed
        }

        let seconds = daysFromCivil(year: year, month: month, day: day) * 86_400
            + hour * 3_600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func parseOffset(_ text: String) -> Int? {
        guard text.count == 5, let sign = text.first, sign == "+" || sign == "-",
              let hours = Int(text.dropFirst().prefix(2)),
              let minutes = Int(text.suffix(2))
        else { return nil }
        let total = hours * 3_600 + minutes * 60
        return sign == "-" ? -total : total
    }

    /// Tage seit 1970-01-01 (proleptischer gregorianischer Kalender, Howard Hinnant).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
