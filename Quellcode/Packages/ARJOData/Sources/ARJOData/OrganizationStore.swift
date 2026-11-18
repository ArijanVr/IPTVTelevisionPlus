import ARJOCore
import Foundation
import SwiftData

/// Nutzerdaten (später per CloudKit synchronisiert): Standardwerte statt Pflichtfelder, keine Eindeutigkeits-Constraints.
@Model
final class PreferenceRecord {
    var profileID: UUID = UUID()
    var key: String = ""
    var isFavorite: Bool = false
    var favoriteOrder: Int = 0
    var isHidden: Bool = false
    var customName: String?
    var sortIndex: Int?
    var updatedAt: Date = Date.now

    init(profileID: UUID, preference: Preference) {
        self.profileID = profileID
        key = preference.key
        apply(preference)
    }

    func apply(_ preference: Preference) {
        isFavorite = preference.isFavorite
        favoriteOrder = preference.favoriteOrder
        isHidden = preference.isHidden
        customName = preference.customName
        sortIndex = preference.sortIndex
        updatedAt = .now
    }

    var preference: Preference {
        Preference(key: key, isFavorite: isFavorite, favoriteOrder: favoriteOrder, isHidden: isHidden, customName: customName, sortIndex: sortIndex)
    }
}

@Model
final class FolderRecord {
    var profileID: UUID = UUID()
    var folderID: UUID = UUID()
    var name: String = ""
    var sortIndex: Int = 0
    var channelIDs: [String] = []
    var updatedAt: Date = Date.now

    init(profileID: UUID, folder: ChannelFolder, sortIndex: Int) {
        self.profileID = profileID
        folderID = folder.id
        self.sortIndex = sortIndex
        apply(folder)
    }

    func apply(_ folder: ChannelFolder) {
        name = folder.name
        channelIDs = folder.channelIDs
        updatedAt = .now
    }

    var folder: ChannelFolder { ChannelFolder(id: folderID, name: name, channelIDs: channelIDs) }
}

@ModelActor
actor OrganizationActor {
    func preferences(for profileID: UUID) throws -> [String: Preference] {
        let descriptor = FetchDescriptor<PreferenceRecord>(predicate: #Predicate { $0.profileID == profileID })
        return Dictionary(
            try modelContext.fetch(descriptor).map { ($0.key, $0.preference) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func save(_ preference: Preference, for profileID: UUID) throws {
        let existing = try record(profileID: profileID, key: preference.key)
        switch (existing, preference.isDefault) {
        case (let record?, true): modelContext.delete(record)
        case (let record?, false): record.apply(preference)
        case (nil, false): modelContext.insert(PreferenceRecord(profileID: profileID, preference: preference))
        case (nil, true): return
        }
        try modelContext.save()
    }

    func setFavoriteOrder(_ channelIDs: [String], for profileID: UUID) throws {
        for (index, channelID) in channelIDs.enumerated() {
            guard let record = try record(profileID: profileID, key: PreferenceKey.channel(channelID)), record.isFavorite else { continue }
            record.favoriteOrder = index
            record.updatedAt = .now
        }
        try modelContext.save()
    }

    func folders(for profileID: UUID) throws -> [ChannelFolder] {
        let descriptor = FetchDescriptor<FolderRecord>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return try modelContext.fetch(descriptor).map(\.folder)
    }

    func save(_ folder: ChannelFolder, for profileID: UUID) throws {
        let folderID = folder.id
        var descriptor = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.profileID == profileID && $0.folderID == folderID })
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.apply(folder)
        } else {
            let count = try modelContext.fetchCount(FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.profileID == profileID }))
            modelContext.insert(FolderRecord(profileID: profileID, folder: folder, sortIndex: count))
        }
        try modelContext.save()
    }

    func deleteFolder(id: UUID, for profileID: UUID) throws {
        try modelContext.delete(model: FolderRecord.self, where: #Predicate { $0.profileID == profileID && $0.folderID == id })
        try modelContext.save()
    }

    func deleteOrganization(for profileID: UUID) throws {
        try modelContext.delete(model: PreferenceRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.delete(model: FolderRecord.self, where: #Predicate { $0.profileID == profileID })
        try modelContext.save()
    }

    private func record(profileID: UUID, key: String) throws -> PreferenceRecord? {
        var descriptor = FetchDescriptor<PreferenceRecord>(predicate: #Predicate { $0.profileID == profileID && $0.key == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

public struct SwiftDataOrganizationRepository: OrganizationRepository {
    private let actor: OrganizationActor

    init(container: ModelContainer) {
        actor = OrganizationActor(modelContainer: container)
    }

    public func preferences(for profileID: UUID) async throws -> [String: Preference] {
        try await actor.preferences(for: profileID)
    }

    public func save(_ preference: Preference, for profileID: UUID) async throws {
        try await actor.save(preference, for: profileID)
    }

    public func setFavoriteOrder(_ channelIDs: [String], for profileID: UUID) async throws {
        try await actor.setFavoriteOrder(channelIDs, for: profileID)
    }

    public func folders(for profileID: UUID) async throws -> [ChannelFolder] {
        try await actor.folders(for: profileID)
    }

    public func save(_ folder: ChannelFolder, for profileID: UUID) async throws {
        try await actor.save(folder, for: profileID)
    }

    public func deleteFolder(id: UUID, for profileID: UUID) async throws {
        try await actor.deleteFolder(id: id, for: profileID)
    }

    public func deleteOrganization(for profileID: UUID) async throws {
        try await actor.deleteOrganization(for: profileID)
    }
}
