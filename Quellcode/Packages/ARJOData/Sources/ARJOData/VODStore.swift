import ARJOCore
import Foundation
import SwiftData

@Model
final class VODRecord {
    #Index<VODRecord>([\.profileID, \.kindRawValue, \.importID, \.groupName])

    var profileID: UUID
    var kindRawValue: String
    var importID: UUID
    var sourceID: Int
    var name: String
    var posterURLString: String?
    var groupName: String
    var rating: Double?
    var year: String?
    var containerExtension: String?
    var addedAt: Date?
    var streamURLString: String?
    var seasonsJSON: Data?
    var sortIndex: Int

    init(item: VODItem, profileID: UUID, importID: UUID, sortIndex: Int) {
        self.profileID = profileID
        self.importID = importID
        kindRawValue = item.kind.rawValue
        sourceID = item.sourceID
        name = item.name
        posterURLString = item.posterURL?.absoluteString
        groupName = item.groupName
        rating = item.rating
        year = item.year
        containerExtension = item.containerExtension
        addedAt = item.addedAt
        streamURLString = item.streamURL?.absoluteString
        seasonsJSON = item.seasons.flatMap { try? JSONEncoder().encode($0) }
        self.sortIndex = sortIndex
    }

    var item: VODItem? {
        VODKind(rawValue: kindRawValue).map {
            VODItem(
                kind: $0, sourceID: sourceID, name: name, posterURL: posterURLString.flatMap { URL(string: $0) },
                groupName: groupName, rating: rating, year: year, containerExtension: containerExtension, addedAt: addedAt,
                streamURL: streamURLString.flatMap { URL(string: $0) },
                seasons: seasonsJSON.flatMap { try? JSONDecoder().decode([Season].self, from: $0) }
            )
        }
    }
}

@Model
final class VODGroupRecord {
    var profileID: UUID
    var kindRawValue: String
    var name: String
    var itemCount: Int
    var sortIndex: Int

    init(profileID: UUID, kind: VODKind, name: String, itemCount: Int, sortIndex: Int) {
        self.profileID = profileID
        kindRawValue = kind.rawValue
        self.name = name
        self.itemCount = itemCount
        self.sortIndex = sortIndex
    }
}

/// Zeigt je Profil und Art auf den zuletzt vollständig importierten Stand.
@Model
final class VODStateRecord {
    var profileID: UUID
    var kindRawValue: String
    var importID: UUID
    var updatedAt: Date

    init(profileID: UUID, kind: VODKind, importID: UUID, updatedAt: Date = .now) {
        self.profileID = profileID
        kindRawValue = kind.rawValue
        self.importID = importID
        self.updatedAt = updatedAt
    }
}

@ModelActor
actor VODActor {
    private static let batchSize = 2_000

    func importItems(for profileID: UUID, kind: VODKind, from stream: AsyncThrowingStream<VODItem, Error>) async throws {
        let kindRaw = kind.rawValue
        let importID = UUID()
        var groupCounts: [String: Int] = [:]
        var groupOrder: [String] = []
        var count = 0

        var batchContext = ModelContext(modelContainer)
        for try await item in stream {
            batchContext.insert(VODRecord(item: item, profileID: profileID, importID: importID, sortIndex: count))
            if groupCounts[item.groupName] == nil { groupOrder.append(item.groupName) }
            groupCounts[item.groupName, default: 0] += 1
            count += 1
            if count % Self.batchSize == 0 {
                try batchContext.save()
                batchContext = ModelContext(modelContainer)
            }
        }
        try batchContext.save()

        try modelContext.delete(model: VODGroupRecord.self, where: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw })
        try modelContext.delete(model: VODStateRecord.self, where: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw })
        for (index, name) in groupOrder.enumerated() {
            modelContext.insert(VODGroupRecord(profileID: profileID, kind: kind, name: name, itemCount: groupCounts[name] ?? 0, sortIndex: index))
        }
        modelContext.insert(VODStateRecord(profileID: profileID, kind: kind, importID: importID))
        try modelContext.save()

        try modelContext.delete(
            model: VODRecord.self,
            where: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw && $0.importID != importID }
        )
        try modelContext.save()
    }

    func groups(for profileID: UUID, kind: VODKind) throws -> [ChannelGroup] {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<VODGroupRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return try modelContext.fetch(descriptor).map { ChannelGroup(name: $0.name, channelCount: $0.itemCount) }
    }

    func items(for profileID: UUID, kind: VODKind, group: String, limit: Int) throws -> [VODItem] {
        let kindRaw = kind.rawValue
        var stateDescriptor = FetchDescriptor<VODStateRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw }
        )
        stateDescriptor.fetchLimit = 1
        guard let importID = try modelContext.fetch(stateDescriptor).first?.importID else { return [] }

        var descriptor = FetchDescriptor<VODRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.kindRawValue == kindRaw && $0.importID == importID && $0.groupName == group
            },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).compactMap(\.item)
    }

    func searchItems(for profileID: UUID, kind: VODKind, query: String, limit: Int) throws -> [VODItem] {
        let kindRaw = kind.rawValue
        var stateDescriptor = FetchDescriptor<VODStateRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw }
        )
        stateDescriptor.fetchLimit = 1
        guard let importID = try modelContext.fetch(stateDescriptor).first?.importID else { return [] }

        var descriptor = FetchDescriptor<VODRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.kindRawValue == kindRaw && $0.importID == importID
                    && $0.name.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).compactMap(\.item)
    }

    func recentItems(for profileID: UUID, kind: VODKind, limit: Int) throws -> [VODItem] {
        let kindRaw = kind.rawValue
        var stateDescriptor = FetchDescriptor<VODStateRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw }
        )
        stateDescriptor.fetchLimit = 1
        guard let importID = try modelContext.fetch(stateDescriptor).first?.importID else { return [] }

        var descriptor = FetchDescriptor<VODRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.kindRawValue == kindRaw && $0.importID == importID && $0.addedAt != nil
            },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse), SortDescriptor(\.sortIndex)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).compactMap(\.item)
    }

    func item(for profileID: UUID, kind: VODKind, sourceID: Int) throws -> VODItem? {
        let kindRaw = kind.rawValue
        var stateDescriptor = FetchDescriptor<VODStateRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw }
        )
        stateDescriptor.fetchLimit = 1
        guard let importID = try modelContext.fetch(stateDescriptor).first?.importID else { return nil }

        var descriptor = FetchDescriptor<VODRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.kindRawValue == kindRaw && $0.importID == importID && $0.sourceID == sourceID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.item
    }

    func lastUpdate(for profileID: UUID, kind: VODKind) throws -> Date? {
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<VODStateRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.kindRawValue == kindRaw }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.updatedAt
    }

    func deleteVOD(for profileID: UUID) throws {
        try modelContext.delete(model: VODRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.delete(model: VODGroupRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.delete(model: VODStateRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.save()
    }
}

public struct SwiftDataVODRepository: VODRepository {
    private let actor: VODActor

    /// Eigene Datei, nie mit iCloud synchronisiert.
    public init(inMemory: Bool = false) throws {
        let schema = Schema([VODRecord.self, VODGroupRecord.self, VODStateRecord.self])
        let configuration = ModelConfiguration("VOD", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        actor = VODActor(modelContainer: try ModelContainer(for: schema, configurations: [configuration]))
    }

    public func importItems(for profileID: UUID, kind: VODKind, from items: AsyncThrowingStream<VODItem, Error>) async throws {
        try await actor.importItems(for: profileID, kind: kind, from: items)
    }

    public func groups(for profileID: UUID, kind: VODKind) async throws -> [ChannelGroup] {
        try await actor.groups(for: profileID, kind: kind)
    }

    public func items(for profileID: UUID, kind: VODKind, group: String, limit: Int) async throws -> [VODItem] {
        try await actor.items(for: profileID, kind: kind, group: group, limit: limit)
    }

    public func recentItems(for profileID: UUID, kind: VODKind, limit: Int) async throws -> [VODItem] {
        try await actor.recentItems(for: profileID, kind: kind, limit: limit)
    }

    public func item(for profileID: UUID, kind: VODKind, sourceID: Int) async throws -> VODItem? {
        try await actor.item(for: profileID, kind: kind, sourceID: sourceID)
    }

    public func lastUpdate(for profileID: UUID, kind: VODKind) async throws -> Date? {
        try await actor.lastUpdate(for: profileID, kind: kind)
    }

    public func deleteVOD(for profileID: UUID) async throws {
        try await actor.deleteVOD(for: profileID)
    }

    public func searchItems(for profileID: UUID, kind: VODKind, query: String, limit: Int) async throws -> [VODItem] {
        try await actor.searchItems(for: profileID, kind: kind, query: query, limit: limit)
    }
}
