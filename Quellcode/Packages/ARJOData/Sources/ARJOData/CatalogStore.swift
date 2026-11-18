import ARJOCore
import Foundation
import SwiftData

@ModelActor
actor CatalogActor {
    private static let batchSize = 2_000
    /// Zwischenspeicher der Nummern pro Profil (Vorwärts und Rückwärts), damit Abfragen nicht jedes Mal dekodieren.
    private var numberCache: [UUID: (byID: [String: Int], byNumber: [Int: String])] = [:]

    func importChannels(for profileID: UUID, from stream: AsyncThrowingStream<Channel, Error>) async throws {
        let importID = UUID()
        var groupCounts: [String: Int] = [:]
        var groupOrder: [String] = []
        var count = 0
        var candidates: [ChannelNumbering.Candidate] = []

        // Eigener Kontext pro Batch: sonst hält der Kontext alle 50'000 Objekte im Speicher.
        var batchContext = ModelContext(modelContainer)
        for try await channel in stream {
            batchContext.insert(ChannelRecord(channel: channel, profileID: profileID, importID: importID, sortIndex: count))
            candidates.append(.init(id: channel.id, sourceNumber: channel.sourceNumber))
            if groupCounts[channel.groupName] == nil { groupOrder.append(channel.groupName) }
            groupCounts[channel.groupName, default: 0] += 1
            count += 1
            if count % Self.batchSize == 0 {
                try batchContext.save()
                batchContext = ModelContext(modelContainer)
            }
        }

        // Feste Nummern: bisherige bleiben, neue Sender bekommen die nächste freie.
        let assigned = ChannelNumbering.assign(candidates, existing: try loadNumbers(for: profileID).byID)
        try modelContext.delete(model: ChannelNumbersRecord.self, where: #Predicate { $0.profileID == profileID })
        batchContext.insert(ChannelNumbersRecord(profileID: profileID, numbers: assigned.numbers))
        numberCache[profileID] = nil

        // Gruppen und Zeiger auf den neuen Stand wechseln in einer einzigen Transaktion.
        try modelContext.delete(model: GroupRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.delete(model: CatalogStateRecord.self, where: #Predicate { $0.profileID == profileID })
        for (index, name) in groupOrder.enumerated() {
            batchContext.insert(GroupRecord(profileID: profileID, name: name, channelCount: groupCounts[name] ?? 0, sortIndex: index))
        }
        batchContext.insert(CatalogStateRecord(profileID: profileID, importID: importID))
        try modelContext.save()
        try batchContext.save()

        try modelContext.delete(
            model: ChannelRecord.self,
            where: #Predicate { $0.profileID == profileID && $0.importID != importID }
        )
        try modelContext.save()
    }

    func groups(for profileID: UUID) throws -> [ChannelGroup] {
        let descriptor = FetchDescriptor<GroupRecord>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return try modelContext.fetch(descriptor).map { ChannelGroup(name: $0.name, channelCount: $0.channelCount) }
    }

    func channels(for profileID: UUID, group: String, limit: Int) throws -> [Channel] {
        guard let importID = try currentImportID(for: profileID) else { return [] }
        var descriptor = FetchDescriptor<ChannelRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.importID == importID && $0.groupName == group },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        descriptor.fetchLimit = limit
        let numbers = try loadNumbers(for: profileID).byID
        return try modelContext.fetch(descriptor).compactMap(\.channel).map { withNumber($0, numbers) }
            .sorted { ($0.number ?? .max) < ($1.number ?? .max) }
    }

    func channel(id: String, for profileID: UUID) throws -> Channel? {
        guard let importID = try currentImportID(for: profileID) else { return nil }
        var descriptor = FetchDescriptor<ChannelRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.importID == importID && $0.channelID == id }
        )
        descriptor.fetchLimit = 1
        guard let channel = try modelContext.fetch(descriptor).first?.channel else { return nil }
        return withNumber(channel, try loadNumbers(for: profileID).byID)
    }

    func channel(number: Int, for profileID: UUID) throws -> Channel? {
        guard let id = try loadNumbers(for: profileID).byNumber[number] else { return nil }
        return try channel(id: id, for: profileID)
    }

    func firstChannel(for profileID: UUID) throws -> Channel? {
        let numbers = try loadNumbers(for: profileID)
        guard let lowest = numbers.byNumber.keys.min() else { return nil }
        return try channel(number: lowest, for: profileID)
    }

    func setNumber(_ number: Int, forChannelID id: String, for profileID: UUID) throws {
        var byID = try loadNumbers(for: profileID).byID
        guard number >= 1, let old = byID[id], old != number else { return }
        if let other = byID.first(where: { $0.value == number })?.key { byID[other] = old }
        byID[id] = number
        try saveNumbers(byID, for: profileID)
    }

    func renumberByGroups(_ order: [String], for profileID: UUID) throws {
        let current = try loadNumbers(for: profileID).byID
        guard let importID = try currentImportID(for: profileID) else { return }
        let all = try modelContext.fetch(FetchDescriptor<GroupRecord>(
            predicate: #Predicate { $0.profileID == profileID }, sortBy: [SortDescriptor(\.sortIndex)])).map(\.name)
        let names = order.filter(all.contains) + all.filter { !order.contains($0) }
        var result: [String: Int] = [:]
        var next = 1
        for name in names {
            var descriptor = FetchDescriptor<ChannelRecord>(
                predicate: #Predicate { $0.profileID == profileID && $0.importID == importID && $0.groupName == name })
            descriptor.propertiesToFetch = [\.channelID]
            let ids = try modelContext.fetch(descriptor).map(\.channelID)
                .sorted { (current[$0] ?? .max, $0) < (current[$1] ?? .max, $1) }
            for id in ids where result[id] == nil { result[id] = next; next += 1 }
        }
        try saveNumbers(result, for: profileID)
    }

    private func saveNumbers(_ numbers: [String: Int], for profileID: UUID) throws {
        try modelContext.delete(model: ChannelNumbersRecord.self, where: #Predicate { $0.profileID == profileID })
        modelContext.insert(ChannelNumbersRecord(profileID: profileID, numbers: numbers))
        try modelContext.save()
        numberCache[profileID] = nil
    }

    private func loadNumbers(for profileID: UUID) throws -> (byID: [String: Int], byNumber: [Int: String]) {
        if let cached = numberCache[profileID] { return cached }
        var descriptor = FetchDescriptor<ChannelNumbersRecord>(predicate: #Predicate { $0.profileID == profileID })
        descriptor.fetchLimit = 1
        let byID = try modelContext.fetch(descriptor).first?.numbers ?? [:]
        let loaded = (byID: byID, byNumber: Dictionary(byID.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first }))
        numberCache[profileID] = loaded
        return loaded
    }

    private func withNumber(_ channel: Channel, _ numbers: [String: Int]) -> Channel {
        var channel = channel
        channel.number = numbers[channel.id]
        return channel
    }

    func epgChannelIDs(for profileID: UUID) throws -> Set<String> {
        guard let importID = try currentImportID(for: profileID) else { return [] }
        var descriptor = FetchDescriptor<ChannelRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.importID == importID && $0.epgChannelID != nil }
        )
        descriptor.propertiesToFetch = [\.epgChannelID]
        return Set(try modelContext.fetch(descriptor).compactMap(\.epgChannelID))
    }

    func searchChannels(for profileID: UUID, query: String, limit: Int) throws -> [Channel] {
        guard let importID = try currentImportID(for: profileID) else { return [] }
        var descriptor = FetchDescriptor<ChannelRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.importID == importID && $0.name.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        descriptor.fetchLimit = limit
        let numbers = try loadNumbers(for: profileID).byID
        return try modelContext.fetch(descriptor).compactMap(\.channel).map { withNumber($0, numbers) }
    }

    func channels(forEPGIDs ids: [String], for profileID: UUID) throws -> [String: Channel] {
        guard let importID = try currentImportID(for: profileID) else { return [:] }
        // Eine Abfrage pro ID: SwiftData kann `IN` über optionale Felder nicht in SQL übersetzen.
        var result: [String: Channel] = [:]
        for id in Set(ids) {
            var descriptor = FetchDescriptor<ChannelRecord>(
                predicate: #Predicate { $0.profileID == profileID && $0.importID == importID && $0.epgChannelID == id },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
            descriptor.fetchLimit = 1
            if let channel = try modelContext.fetch(descriptor).first?.channel {
                result[id] = withNumber(channel, try loadNumbers(for: profileID).byID)
            }
        }
        return result
    }

    func lastUpdate(for profileID: UUID) throws -> Date? {
        var descriptor = FetchDescriptor<CatalogStateRecord>(predicate: #Predicate { $0.profileID == profileID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.updatedAt
    }

    func deleteCatalog(for profileID: UUID) throws {
        try modelContext.delete(model: ChannelRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.delete(model: GroupRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.delete(model: CatalogStateRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.delete(model: ChannelNumbersRecord.self, where: #Predicate { $0.profileID == profileID })
        numberCache[profileID] = nil
        try modelContext.save()
    }

    private func currentImportID(for profileID: UUID) throws -> UUID? {
        var descriptor = FetchDescriptor<CatalogStateRecord>(predicate: #Predicate { $0.profileID == profileID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.importID
    }
}

public struct SwiftDataCatalogRepository: CatalogRepository {
    private let actor: CatalogActor

    /// Der Katalog liegt in einer eigenen Datei und wird nie mit iCloud synchronisiert.
    public init(inMemory: Bool = false) throws {
        let schema = Schema([ChannelRecord.self, GroupRecord.self, CatalogStateRecord.self, ChannelNumbersRecord.self])
        let configuration = ModelConfiguration("Catalog", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        actor = CatalogActor(modelContainer: try ModelContainer(for: schema, configurations: [configuration]))
    }

    public func importChannels(for profileID: UUID, from channels: AsyncThrowingStream<Channel, Error>) async throws {
        try await actor.importChannels(for: profileID, from: channels)
    }

    public func groups(for profileID: UUID) async throws -> [ChannelGroup] {
        try await actor.groups(for: profileID)
    }

    public func channels(for profileID: UUID, group: String, limit: Int) async throws -> [Channel] {
        try await actor.channels(for: profileID, group: group, limit: limit)
    }

    public func channel(id: String, for profileID: UUID) async throws -> Channel? {
        try await actor.channel(id: id, for: profileID)
    }

    public func deleteCatalog(for profileID: UUID) async throws {
        try await actor.deleteCatalog(for: profileID)
    }

    public func lastUpdate(for profileID: UUID) async throws -> Date? {
        try await actor.lastUpdate(for: profileID)
    }

    public func epgChannelIDs(for profileID: UUID) async throws -> Set<String> {
        try await actor.epgChannelIDs(for: profileID)
    }

    public func searchChannels(for profileID: UUID, query: String, limit: Int) async throws -> [Channel] {
        try await actor.searchChannels(for: profileID, query: query, limit: limit)
    }

    public func channels(forEPGIDs ids: [String], for profileID: UUID) async throws -> [String: Channel] {
        try await actor.channels(forEPGIDs: ids, for: profileID)
    }

    public func channel(number: Int, for profileID: UUID) async throws -> Channel? {
        try await actor.channel(number: number, for: profileID)
    }

    public func firstChannel(for profileID: UUID) async throws -> Channel? {
        try await actor.firstChannel(for: profileID)
    }

    public func setNumber(_ number: Int, forChannelID id: String, for profileID: UUID) async throws {
        try await actor.setNumber(number, forChannelID: id, for: profileID)
    }

    public func renumberByGroups(_ groupOrder: [String], for profileID: UUID) async throws {
        try await actor.renumberByGroups(groupOrder, for: profileID)
    }
}
