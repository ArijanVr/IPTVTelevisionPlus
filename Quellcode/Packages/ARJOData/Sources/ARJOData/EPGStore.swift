import ARJOCore
import Foundation
import SwiftData

@Model
final class ProgrammeRecord {
    #Index<ProgrammeRecord>([\.profileID, \.importID, \.channelID, \.start])

    var profileID: UUID
    var importID: UUID
    var channelID: String
    var start: Date
    var stop: Date
    var title: String
    var subtitle: String?
    var programmeDescription: String?
    var category: String?
    var iconURLString: String?

    init(programme: EPGProgramme, profileID: UUID, importID: UUID) {
        self.profileID = profileID
        self.importID = importID
        channelID = programme.channelID
        start = programme.start
        stop = programme.stop
        title = programme.title
        subtitle = programme.subtitle
        programmeDescription = programme.description
        category = programme.category
        iconURLString = programme.iconURL?.absoluteString
    }

    var programme: EPGProgramme {
        EPGProgramme(
            channelID: channelID, start: start, stop: stop, title: title,
            subtitle: subtitle, description: programmeDescription, category: category,
            iconURL: iconURLString.flatMap { URL(string: $0) }
        )
    }
}

/// Zeigt auf den zuletzt vollständig importierten EPG-Stand (siehe `CatalogStateRecord`).
@Model
final class EPGStateRecord {
    var profileID: UUID
    var importID: UUID
    var updatedAt: Date

    init(profileID: UUID, importID: UUID, updatedAt: Date = .now) {
        self.profileID = profileID
        self.importID = importID
        self.updatedAt = updatedAt
    }
}

@ModelActor
actor EPGActor {
    private static let batchSize = 5_000
    private static let nextHorizon: TimeInterval = 12 * 3_600

    func importProgrammes(for profileID: UUID, from stream: AsyncThrowingStream<EPGProgramme, Error>) async throws {
        let importID = UUID()
        var count = 0
        var batchContext = ModelContext(modelContainer)
        for try await programme in stream {
            batchContext.insert(ProgrammeRecord(programme: programme, profileID: profileID, importID: importID))
            count += 1
            if count % Self.batchSize == 0 {
                try batchContext.save()
                batchContext = ModelContext(modelContainer)
            }
        }
        try batchContext.save()

        try modelContext.delete(model: EPGStateRecord.self, where: #Predicate { $0.profileID == profileID })
        modelContext.insert(EPGStateRecord(profileID: profileID, importID: importID))
        try modelContext.save()

        try modelContext.delete(
            model: ProgrammeRecord.self,
            where: #Predicate { $0.profileID == profileID && $0.importID != importID }
        )
        try modelContext.save()
    }

    func programmes(for profileID: UUID, channelIDs: [String], from: Date, to: Date) throws -> [EPGProgramme] {
        guard let importID = try currentImportID(for: profileID) else { return [] }
        let descriptor = FetchDescriptor<ProgrammeRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.importID == importID && channelIDs.contains($0.channelID)
                    && $0.stop > from && $0.start < to
            },
            sortBy: [SortDescriptor(\.start)]
        )
        return try modelContext.fetch(descriptor).map(\.programme)
    }

    func nowNext(for profileID: UUID, channelIDs: [String], at date: Date) throws -> [String: NowNext] {
        let horizon = date.addingTimeInterval(Self.nextHorizon)
        let upcoming = try programmes(for: profileID, channelIDs: channelIDs, from: date, to: horizon)

        var result: [String: NowNext] = [:]
        for (channelID, list) in Dictionary(grouping: upcoming, by: \.channelID) {
            let airing = list.first.flatMap { $0.isAiring(at: date) ? $0 : nil }
            result[channelID] = NowNext(now: airing, next: airing == nil ? list.first : list.dropFirst().first)
        }
        return result
    }

    func searchProgrammes(for profileID: UUID, query: String, from: Date, to: Date, limit: Int) throws -> [EPGProgramme] {
        guard let importID = try currentImportID(for: profileID) else { return [] }
        var descriptor = FetchDescriptor<ProgrammeRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.importID == importID && $0.stop > from && $0.start < to
                    && $0.title.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.start)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.programme)
    }

    func lastUpdate(for profileID: UUID) throws -> Date? {
        var descriptor = FetchDescriptor<EPGStateRecord>(predicate: #Predicate { $0.profileID == profileID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.updatedAt
    }

    func deleteEPG(for profileID: UUID) throws {
        try modelContext.delete(model: ProgrammeRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.delete(model: EPGStateRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.save()
    }

    private func currentImportID(for profileID: UUID) throws -> UUID? {
        var descriptor = FetchDescriptor<EPGStateRecord>(predicate: #Predicate { $0.profileID == profileID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.importID
    }
}

public struct SwiftDataEPGRepository: EPGRepository {
    private let actor: EPGActor

    /// Eigene Datei, damit sich das EPG unabhängig vom Katalog löschen und neu laden lässt.
    public init(inMemory: Bool = false) throws {
        let schema = Schema([ProgrammeRecord.self, EPGStateRecord.self])
        let configuration = ModelConfiguration("EPG", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        actor = EPGActor(modelContainer: try ModelContainer(for: schema, configurations: [configuration]))
    }

    public func importProgrammes(for profileID: UUID, from programmes: AsyncThrowingStream<EPGProgramme, Error>) async throws {
        try await actor.importProgrammes(for: profileID, from: programmes)
    }

    public func programmes(for profileID: UUID, channelIDs: [String], from: Date, to: Date) async throws -> [EPGProgramme] {
        try await actor.programmes(for: profileID, channelIDs: channelIDs, from: from, to: to)
    }

    public func nowNext(for profileID: UUID, channelIDs: [String], at date: Date) async throws -> [String: NowNext] {
        try await actor.nowNext(for: profileID, channelIDs: channelIDs, at: date)
    }

    public func searchProgrammes(for profileID: UUID, query: String, from: Date, to: Date, limit: Int) async throws -> [EPGProgramme] {
        try await actor.searchProgrammes(for: profileID, query: query, from: from, to: to, limit: limit)
    }

    public func lastUpdate(for profileID: UUID) async throws -> Date? {
        try await actor.lastUpdate(for: profileID)
    }

    public func deleteEPG(for profileID: UUID) async throws {
        try await actor.deleteEPG(for: profileID)
    }
}
