import Foundation

/// Liest `key="value"`-Attribute einer `#EXTM3U`- oder `#EXTINF`-Zeile.
/// Kommas und Leerzeichen in Anführungszeichen gehören zum Wert.
enum ExtInfScanner {
    struct Result {
        var attributes: [String: String] = [:]
        /// Text nach dem ersten Komma ausserhalb von Anführungszeichen (Sendername).
        var title: String?
    }

    /// - Parameter hasDuration: `true` bei `#EXTINF` (erstes Token ist die Laufzeit).
    static func scan(_ body: Substring, hasDuration: Bool) -> Result {
        var result = Result()
        var index = body.startIndex
        let end = body.endIndex

        if hasDuration {
            while index < end, body[index] != " ", body[index] != "," {
                index = body.index(after: index)
            }
        }

        while index < end {
            while index < end, body[index] == " " {
                index = body.index(after: index)
            }
            guard index < end else { break }

            if body[index] == "," {
                let titleStart = body.index(after: index)
                result.title = body[titleStart...].trimmingCharacters(in: .whitespaces)
                break
            }

            let keyStart = index
            while index < end, body[index] != "=", body[index] != ",", body[index] != " " {
                index = body.index(after: index)
            }
            guard index < end, body[index] == "=" else { continue }
            let key = body[keyStart..<index].lowercased()
            index = body.index(after: index)

            let value: Substring
            if index < end, body[index] == "\"" {
                index = body.index(after: index)
                let valueStart = index
                while index < end, body[index] != "\"" {
                    index = body.index(after: index)
                }
                value = body[valueStart..<index]
                if index < end { index = body.index(after: index) }
            } else {
                let valueStart = index
                while index < end, body[index] != " ", body[index] != "," {
                    index = body.index(after: index)
                }
                value = body[valueStart..<index]
            }
            result.attributes[key] = String(value)
        }
        return result
    }
}
