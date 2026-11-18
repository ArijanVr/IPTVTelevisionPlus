import Foundation

/// Woher der Stream eines Senders kommt. Bei Xtream wird die URL erst beim Abspielen
/// aus den Keychain-Zugangsdaten gebaut, damit kein Passwort im Katalog landet.
public enum ChannelSource: Sendable, Hashable, Codable {
    case xtream(streamID: Int)
    case url(URL)
}

public struct Channel: Sendable, Hashable, Codable, Identifiable {
    /// Eindeutig innerhalb eines Profils (Xtream: Stream-ID, M3U: `ContentIdentity.channelID`, ohne Zugangsdaten).
    public var id: String
    public var name: String
    public var source: ChannelSource
    public var logoURL: URL?
    public var groupName: String
    public var epgChannelID: String?
    /// Tage, die der Anbieter rückwirkend bereithält (Catch-up/Timeshift); `nil` = nicht unterstützt.
    public var archiveDays: Int?
    /// Catch-up-Art aus der M3U-Playlist (`default`, `append`, `shift`, `flussonic` …).
    public var catchupType: String?
    /// Adress-Vorlage aus der M3U-Playlist (`catchup-source`).
    public var catchupTemplate: String?
    /// Feste Kanalnummer, vom Katalog nach dem Import vergeben (`ChannelNumbering`); `nil` nur vor der Vergabe.
    public var number: Int?
    /// Nummer, die die Quelle selbst nennt (M3U `tvg-chno`, Xtream `num`). Nur Vorschlag für die Vergabe.
    public var sourceNumber: Int?

    public static let ungroupedName = "Ohne Gruppe"

    public var supportsCatchup: Bool { (archiveDays ?? 0) > 0 }

    public init(
        id: String,
        name: String,
        source: ChannelSource,
        logoURL: URL? = nil,
        groupName: String = Channel.ungroupedName,
        epgChannelID: String? = nil,
        archiveDays: Int? = nil,
        catchupType: String? = nil,
        catchupTemplate: String? = nil,
        number: Int? = nil,
        sourceNumber: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.logoURL = logoURL
        self.groupName = groupName
        self.epgChannelID = epgChannelID
        self.archiveDays = archiveDays
        self.catchupType = catchupType
        self.catchupTemplate = catchupTemplate
        self.number = number
        self.sourceNumber = sourceNumber
    }

    public init(entry: PlaylistEntry) {
        self.init(
            id: ContentIdentity.channelID(for: entry.url),
            name: entry.name,
            source: .url(entry.url),
            logoURL: entry.logoURL,
            groupName: entry.groupTitle ?? Channel.ungroupedName,
            epgChannelID: entry.tvgID,
            // «catchup» ohne Tagesangabe heisst in der Praxis: wenigstens ein Tag.
            archiveDays: entry.catchupDays ?? (entry.catchupType == nil ? nil : 1),
            catchupType: entry.catchupType,
            catchupTemplate: entry.catchupSource,
            sourceNumber: entry.channelNumber
        )
    }
}

public struct ChannelGroup: Sendable, Hashable, Identifiable {
    public var name: String
    public var channelCount: Int
    public var id: String { name }

    public init(name: String, channelCount: Int) {
        self.name = name
        self.channelCount = channelCount
    }
}

public extension AsyncThrowingStream where Failure == Error {
    static func from(_ elements: [Element]) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            elements.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
