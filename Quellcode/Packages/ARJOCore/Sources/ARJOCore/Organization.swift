import Foundation

/// Eigene Einstellungen eines Nutzers zu einem Sender oder einer Gruppe (Favorit, ausgeblendet, umbenannt).
/// Einträge ohne Abweichung vom Standard werden nicht gespeichert.
public struct Preference: Sendable, Codable, Equatable {
    public var key: String
    public var isFavorite = false
    /// Position in der Favoritenliste (aufsteigend).
    public var favoriteOrder = 0
    public var isHidden = false
    public var customName: String?
    /// Eigene Position einer Gruppe (aufsteigend); `nil` = Reihenfolge des Anbieters.
    public var sortIndex: Int?

    public init(
        key: String, isFavorite: Bool = false, favoriteOrder: Int = 0, isHidden: Bool = false,
        customName: String? = nil, sortIndex: Int? = nil
    ) {
        self.key = key
        self.isFavorite = isFavorite
        self.favoriteOrder = favoriteOrder
        self.isHidden = isHidden
        self.customName = customName
        self.sortIndex = sortIndex
    }

    public var isDefault: Bool {
        !isFavorite && !isHidden && (customName?.isEmpty ?? true) && sortIndex == nil
    }
}

public enum PreferenceKey {
    public static func channel(_ id: String) -> String { "channel:\(id)" }
    public static func group(_ area: GroupArea, _ name: String) -> String { "group:\(area.rawValue):\(name)" }
}

/// Ein eigener Ordner mit Sendern in eigener Reihenfolge.
public struct ChannelFolder: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var channelIDs: [String]

    public init(id: UUID = UUID(), name: String, channelIDs: [String] = []) {
        self.id = id
        self.name = name
        self.channelIDs = channelIDs
    }
}

/// Nutzerdaten zur Organisation der Sender (später per CloudKit synchronisiert).
public protocol OrganizationRepository: Sendable {
    /// Alle gespeicherten Einträge eines Profils, nach `Preference.key`.
    func preferences(for profileID: UUID) async throws -> [String: Preference]
    /// Speichert den Eintrag; ein Eintrag ohne Abweichung vom Standard wird gelöscht.
    func save(_ preference: Preference, for profileID: UUID) async throws
    /// Legt die Reihenfolge der Favoriten fest (Index in der Liste = Position).
    func setFavoriteOrder(_ channelIDs: [String], for profileID: UUID) async throws
    func folders(for profileID: UUID) async throws -> [ChannelFolder]
    /// Legt an oder aktualisiert (nach `id`); neue Ordner kommen ans Ende.
    func save(_ folder: ChannelFolder, for profileID: UUID) async throws
    func deleteFolder(id: UUID, for profileID: UUID) async throws
    func deleteOrganization(for profileID: UUID) async throws
}
