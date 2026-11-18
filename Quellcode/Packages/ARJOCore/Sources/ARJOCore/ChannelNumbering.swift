import Foundation

/// Vergibt feste Kanalnummern: eine Nummer pro Sender, in jeder Gruppe gleich, über Playlist-Aktualisierungen stabil.
///
/// Reihenfolge der Quellen: bereits vergebene Nummer (stabil) → Nummer der Quelle (`tvg-chno`/`num`) → fortlaufend.
/// Nutzerzuweisungen (Einstellungen) liegen als `pinned` vor und gehen allem vor.
public enum ChannelNumbering {
    /// Höchste Nummer, die man per Zifferneingabe erreicht (vier Stellen).
    public static let maxTypedNumber = 9999

    public struct Candidate: Sendable, Equatable {
        public var id: String
        public var sourceNumber: Int?

        public init(id: String, sourceNumber: Int?) {
            self.id = id
            self.sourceNumber = sourceNumber
        }
    }

    public struct Result: Sendable, Equatable {
        public var numbers: [String: Int]
        /// Sender, deren Nummer aus der Quelle schon vergeben war und die deshalb eine andere bekamen.
        public var duplicateCount: Int
    }

    /// - Parameters:
    ///   - candidates: alle Sender in Playlist-Reihenfolge.
    ///   - existing: bisher gespeicherte Nummern (Sender-ID → Nummer). Verschwundene Sender werden verworfen.
    ///   - pinned: vom Nutzer festgelegte Nummern; haben Vorrang vor `existing`.
    public static func assign(
        _ candidates: [Candidate],
        existing: [String: Int] = [:],
        pinned: [String: Int] = [:]
    ) -> Result {
        var numbers: [String: Int] = [:]
        numbers.reserveCapacity(candidates.count)
        var used = Set<Int>()
        used.reserveCapacity(candidates.count)

        func take(_ id: String, _ number: Int) -> Bool {
            guard number >= 1, numbers[id] == nil, !used.contains(number) else { return false }
            numbers[id] = number
            used.insert(number)
            return true
        }

        // 1. Nutzerzuweisung, 2. gespeicherte Nummer: beide bleiben, wo sie sind.
        for candidate in candidates { if let n = pinned[candidate.id] { _ = take(candidate.id, n) } }
        for candidate in candidates { if let n = existing[candidate.id] { _ = take(candidate.id, n) } }

        // 3. Nummer der Quelle; der Erste behält sie.
        var duplicates = 0
        var rest: [String] = []
        for candidate in candidates where numbers[candidate.id] == nil {
            if let n = candidate.sourceNumber, n >= 1 {
                if !take(candidate.id, n) { duplicates += 1; rest.append(candidate.id) }
            } else {
                rest.append(candidate.id)
            }
        }

        // 4. Rest fortlaufend. Gab es schon Nummern, kommen neue hinter die höchste (Lücken bleiben frei).
        var next = existing.isEmpty && pinned.isEmpty ? 1 : (used.max() ?? 0) + 1
        for id in rest where numbers[id] == nil {
            while used.contains(next) { next += 1 }
            numbers[id] = next
            used.insert(next)
            next += 1
        }
        return Result(numbers: numbers, duplicateCount: duplicates)
    }
}
