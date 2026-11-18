import Foundation

/// Reine Zustandsmaschine fürs Zappen: Kanal hoch/runter in der Gruppe, Gruppenwechsel, Zifferneingabe, «Letzter Kanal».
/// Kennt keine Wiedergabe und keine Datenbank; wer sie benutzt, lädt die Senderliste einer Gruppe nach `load(group:items:)`.
public struct ChannelNavigator: Sendable, Equatable {
    public struct Item: Sendable, Hashable {
        public var id: String
        public var number: Int

        public init(id: String, number: Int) {
            self.id = id
            self.number = number
        }
    }

    /// Anzeige für das Gruppen-Banner, z. B. «Schweiz · 3 von 12».
    public struct GroupPosition: Sendable, Equatable {
        public var name: String
        public var position: Int
        public var count: Int

        public init(name: String, position: Int, count: Int) {
            self.name = name
            self.position = position
            self.count = count
        }
    }

    /// Sekunden ohne weitere Ziffer, nach denen die Eingabe gilt.
    public static let digitWindow: TimeInterval = 2
    public static let maxDigits = 4

    /// Gruppen in meiner Reihenfolge, ohne ausgeblendete und gesperrte.
    public private(set) var groups: [String]
    public private(set) var currentGroup: String?
    public private(set) var items: [Item] = []
    public private(set) var currentID: String?
    public private(set) var previousID: String?
    public private(set) var digits = ""
    private var lastDigitAt: Date?

    public init(groups: [String]) {
        self.groups = groups
    }

    public var current: Item? { items.first { $0.id == currentID } }

    /// Ersetzt die Gruppenliste (Reihenfolge, Ausblenden oder Sperren geändert). Fehlt die aktuelle Gruppe, bleibt die Liste stehen.
    public mutating func setGroups(_ names: [String]) {
        groups = names
    }

    // MARK: Gruppe und Kanal

    /// Merkt sich die Gruppe, in der gerade ein Sender läuft, ohne ihre Senderliste zu laden.
    public mutating func setCurrentGroup(_ name: String?) {
        currentGroup = name
    }

    /// Stellt die Gruppe samt Senderliste (nach Nummer sortiert) ein und wählt `selecting`, sonst den ersten Sender.
    @discardableResult
    public mutating func load(group: String, items: [Item], selecting id: String? = nil) -> Item? {
        currentGroup = group
        self.items = items.sorted { $0.number < $1.number }
        let target = self.items.first { $0.id == id } ?? self.items.first
        return select(target)
    }

    /// Hoch (-1) / runter (+1) in der Gruppe, am Ende rundum.
    @discardableResult
    public mutating func zap(by offset: Int) -> Item? {
        guard !items.isEmpty else { return nil }
        guard let index = items.firstIndex(where: { $0.id == currentID }) else { return select(items.first) }
        guard items.count > 1 else { return current }
        let next = ((index + offset) % items.count + items.count) % items.count
        return select(items[next])
    }

    /// Name der Gruppe vor (-1) oder nach (+1) der aktuellen, am Ende rundum. Lädt nichts: danach `load(group:items:)` aufrufen.
    public func neighbourGroup(by offset: Int) -> GroupPosition? {
        guard !groups.isEmpty else { return nil }
        let index = currentGroup.flatMap { groups.firstIndex(of: $0) } ?? (offset >= 0 ? -1 : 0)
        let next = ((index + offset) % groups.count + groups.count) % groups.count
        return GroupPosition(name: groups[next], position: next + 1, count: groups.count)
    }

    public var groupPosition: GroupPosition? {
        guard let currentGroup, let index = groups.firstIndex(of: currentGroup) else { return nil }
        return GroupPosition(name: currentGroup, position: index + 1, count: groups.count)
    }

    /// Springt zu einem Sender, der schon in der geladenen Gruppe liegt.
    @discardableResult
    public mutating func select(id: String) -> Item? {
        select(items.first { $0.id == id })
    }

    /// «Letzter Kanal»: zurück zum vorher gesehenen Sender, falls er in der geladenen Gruppe liegt.
    @discardableResult
    public mutating func recallPrevious() -> Item? {
        guard let previousID else { return nil }
        return select(id: previousID)
    }

    private mutating func select(_ item: Item?) -> Item? {
        guard let item else { return nil }
        if item.id != currentID {
            previousID = currentID
            currentID = item.id
        }
        return item
    }

    // MARK: Zifferneingabe

    public var hasPendingDigits: Bool { !digits.isEmpty }

    /// Fügt eine Ziffer an. Nach der vierten Stelle weitere Ziffern ignorieren; führende Nullen zählen nicht.
    public mutating func enter(digit: Int, at now: Date) {
        guard (0...9).contains(digit) else { return }
        if digits.isEmpty, digit == 0 { return }
        if digits.count < Self.maxDigits { digits.append(String(digit)) }
        lastDigitAt = now
    }

    /// Wann die Eingabe ohne weitere Ziffer gilt; `nil` ohne Eingabe.
    public var commitDeadline: Date? { lastDigitAt.map { $0.addingTimeInterval(Self.digitWindow) } }

    /// Beendet die Eingabe und liefert die Nummer (Enter/OK oder Ablauf des Zeitfensters).
    public mutating func commitDigits() -> Int? {
        defer { digits = ""; lastDigitAt = nil }
        return Int(digits)
    }

    public mutating func cancelDigits() {
        digits = ""
        lastDigitAt = nil
    }
}
