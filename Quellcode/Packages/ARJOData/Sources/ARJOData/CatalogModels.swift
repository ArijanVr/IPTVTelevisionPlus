import ARJOCore
import Foundation
import SwiftData

@Model
final class ChannelRecord {
    #Index<ChannelRecord>([\.profileID, \.importID, \.groupName], [\.profileID, \.importID, \.channelID])

    var profileID: UUID
    var importID: UUID
    var channelID: String
    var name: String
    var xtreamStreamID: Int?
    var urlString: String?
    var logoURLString: String?
    var groupName: String
    var epgChannelID: String?
    var archiveDays: Int?
    var catchupType: String?
    var catchupTemplate: String?
    var sortIndex: Int

    init(channel: Channel, profileID: UUID, importID: UUID, sortIndex: Int) {
        self.profileID = profileID
        self.importID = importID
        self.channelID = channel.id
        self.name = channel.name
        switch channel.source {
        case .xtream(let streamID):
            xtreamStreamID = streamID
        case .url(let url):
            urlString = url.absoluteString
        }
        self.logoURLString = channel.logoURL?.absoluteString
        self.groupName = channel.groupName
        self.epgChannelID = channel.epgChannelID
        self.archiveDays = channel.archiveDays
        self.catchupType = channel.catchupType
        self.catchupTemplate = channel.catchupTemplate
        self.sortIndex = sortIndex
    }

    var channel: Channel? {
        let source: ChannelSource
        if let xtreamStreamID {
            source = .xtream(streamID: xtreamStreamID)
        } else if let url = urlString.flatMap({ URL(string: $0) }) {
            source = .url(url)
        } else {
            return nil
        }
        return Channel(
            id: channelID,
            name: name,
            source: source,
            logoURL: logoURLString.flatMap { URL(string: $0) },
            groupName: groupName,
            epgChannelID: epgChannelID,
            archiveDays: archiveDays,
            catchupType: catchupType,
            catchupTemplate: catchupTemplate
        )
    }
}

@Model
final class GroupRecord {
    var profileID: UUID
    var name: String
    var channelCount: Int
    var sortIndex: Int

    init(profileID: UUID, name: String, channelCount: Int, sortIndex: Int) {
        self.profileID = profileID
        self.name = name
        self.channelCount = channelCount
        self.sortIndex = sortIndex
    }
}

/// Zeigt auf den zuletzt vollständig importierten Stand. Zeilen anderer `importID`s
/// (laufender oder abgebrochener Import) sind für Abfragen unsichtbar.
@Model
final class CatalogStateRecord {
    var profileID: UUID
    var importID: UUID
    var updatedAt: Date

    init(profileID: UUID, importID: UUID, updatedAt: Date = .now) {
        self.profileID = profileID
        self.importID = importID
        self.updatedAt = updatedAt
    }
}

/// Feste Kanalnummern eines Profils (Sender-ID → Nummer) als ein JSON-Blatt; bleibt über Katalog-Aktualisierungen erhalten.
@Model
final class ChannelNumbersRecord {
    var profileID: UUID
    var data: Data

    init(profileID: UUID, numbers: [String: Int]) {
        self.profileID = profileID
        self.data = (try? JSONEncoder().encode(numbers)) ?? Data()
    }

    var numbers: [String: Int] { (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:] }
}
