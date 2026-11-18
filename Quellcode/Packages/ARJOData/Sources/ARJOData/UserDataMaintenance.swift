import ARJOCore
import Foundation
import SwiftData

/// Pflege der synchronisierten Nutzerdaten. Alle Schritte sind idempotent: Jedes Gerät führt sie aus und kommt zum
/// selben Ergebnis, auch wenn Daten älterer App-Versionen später über iCloud eintreffen.
@ModelActor
actor UserDataMaintenanceActor {
    /// Ersetzt Kennungen älterer Versionen, die vollständige Playlist-Adressen enthielten (mit möglichen Zugangsdaten
    /// und wechselnden Tokens), durch `ContentIdentity`-Kennungen. Gibt zurück, ob sich etwas geändert hat.
    func migrateLegacyContentIDs() throws -> Bool {
        var changed = false

        for record in try modelContext.fetch(FetchDescriptor<PreferenceRecord>()) {
            guard record.key.hasPrefix("channel:") else { continue }
            let channelID = String(record.key.dropFirst("channel:".count))
            let migrated = ContentIdentity.migratedChannelID(channelID)
            guard migrated != channelID else { continue }
            let newKey = PreferenceKey.channel(migrated)
            let profileID = record.profileID
            let clashing = try modelContext.fetch(FetchDescriptor<PreferenceRecord>(
                predicate: #Predicate { $0.profileID == profileID && $0.key == newKey }
            ))
            if let existing = clashing.first {
                // Beide Fassungen vorhanden (zwei Geräte, unterschiedliche Versionen): die neuere bleibt.
                if record.updatedAt > existing.updatedAt { existing.apply(record.preference) }
                modelContext.delete(record)
            } else {
                record.key = newKey
            }
            changed = true
        }

        for folder in try modelContext.fetch(FetchDescriptor<FolderRecord>()) {
            var seen = Set<String>()
            let migrated = folder.channelIDs.map(ContentIdentity.migratedChannelID).filter { seen.insert($0).inserted }
            guard migrated != folder.channelIDs else { continue }
            folder.channelIDs = migrated
            changed = true
        }

        for profile in try modelContext.fetch(FetchDescriptor<ProfileRecord>()) {
            guard let id = profile.lastChannelID else { continue }
            let migrated = ContentIdentity.migratedChannelID(id)
            guard migrated != id else { continue }
            profile.lastChannelID = migrated
            changed = true
        }

        let legacyProgress = try modelContext.fetch(FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.directURLString != nil }
        ))
        for record in legacyProgress {
            if let url = record.directURLString.flatMap(URL.init(string:)), url.scheme != nil {
                record.streamID = ContentIdentity.mediaID(for: url)
                record.key = "\(record.kindRawValue)-\(record.streamID)"
            }
            record.directURLString = nil
            changed = true
        }

        if changed { try modelContext.save() }
        return changed
    }

    /// Führt Profile derselben Quelle (gleicher `SourceFingerprint`) zusammen, z. B. wenn sich jemand vor dem
    /// ersten Abgleich auf zwei Geräten angemeldet hat. Es bleibt das Profil mit der kleinsten ID, damit alle Geräte
    /// unabhängig voneinander dasselbe wählen. Liefert die zusammengeführten IDs (alt → bleibend).
    func mergeDuplicateProfiles() throws -> [UUID: UUID] {
        let records = try modelContext.fetch(FetchDescriptor<ProfileRecord>())
        let mapping = Self.duplicateMapping(records)
        guard !mapping.isEmpty else { return [:] }

        for (old, keep) in mapping {
            try moveProgress(from: old, to: keep)
            try movePreferences(from: old, to: keep)
            for folder in try modelContext.fetch(FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.profileID == old })) {
                folder.profileID = keep
            }
            try mergeProfileRecords(from: old, into: keep, records: records)
        }
        try remapLockedGroups(mapping)
        try modelContext.save()
        return mapping
    }

    /// Welche Profile `mergeDuplicateProfiles` zusammenführen würde, ohne etwas zu ändern.
    func plannedMerges() throws -> [UUID: UUID] {
        Self.duplicateMapping(try modelContext.fetch(FetchDescriptor<ProfileRecord>()))
    }

    private static func duplicateMapping(_ records: [ProfileRecord]) -> [UUID: UUID] {
        let groups = Dictionary(grouping: records.filter { $0.sourceFingerprint != nil }, by: { $0.sourceFingerprint! })
        var mapping: [UUID: UUID] = [:]
        for group in groups.values {
            let ids = Set(group.map(\.id))
            guard ids.count > 1, let keep = ids.min(by: { $0.uuidString < $1.uuidString }) else { continue }
            for id in ids where id != keep { mapping[id] = keep }
        }
        return mapping
    }

    private func moveProgress(from old: UUID, to keep: UUID) throws {
        let moved = try modelContext.fetch(FetchDescriptor<WatchProgressRecord>(predicate: #Predicate { $0.profileID == old }))
        let existing = try modelContext.fetch(FetchDescriptor<WatchProgressRecord>(predicate: #Predicate { $0.profileID == keep }))
        var byKeyAndDevice = Dictionary(existing.map { ("\($0.key)|\($0.deviceID)", $0) }, uniquingKeysWith: { first, _ in first })
        for record in moved {
            let slot = "\(record.key)|\(record.deviceID)"
            if let other = byKeyAndDevice[slot] {
                // Dasselbe Gerät hat in beiden Profilen geschrieben: der neuere Stand bleibt.
                if WatchProgressRecord.isNewer(record, than: other), let progress = record.progress { other.apply(progress) }
                modelContext.delete(record)
            } else {
                record.profileID = keep
                byKeyAndDevice[slot] = record
            }
        }
    }

    private func movePreferences(from old: UUID, to keep: UUID) throws {
        let moved = try modelContext.fetch(FetchDescriptor<PreferenceRecord>(predicate: #Predicate { $0.profileID == old }))
        let existing = try modelContext.fetch(FetchDescriptor<PreferenceRecord>(predicate: #Predicate { $0.profileID == keep }))
        let byKey = Dictionary(existing.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for record in moved {
            if let other = byKey[record.key] {
                if record.updatedAt > other.updatedAt { other.apply(record.preference) }
                modelContext.delete(record)
            } else {
                record.profileID = keep
            }
        }
    }

    private func mergeProfileRecords(from old: UUID, into keep: UUID, records: [ProfileRecord]) throws {
        let removed = records.filter { $0.id == old }
        if let target = records.first(where: { $0.id == keep }) {
            for record in removed {
                if let time = record.lastChannelUpdatedAt, time > (target.lastChannelUpdatedAt ?? .distantPast) {
                    target.lastChannelID = record.lastChannelID
                    target.lastTimeshiftInstant = record.lastTimeshiftInstant
                    target.lastChannelUpdatedAt = time
                }
                // Eine Löschung des Verlaufs gilt auch nach dem Zusammenführen.
                target.progressClearedAt = [target.progressClearedAt, record.progressClearedAt].compactMap { $0 }.max()
            }
        }
        removed.forEach(modelContext.delete)
    }

    private func remapLockedGroups(_ mapping: [UUID: UUID]) throws {
        for record in try modelContext.fetch(FetchDescriptor<SettingsRecord>()) {
            guard var settings = try? JSONDecoder().decode(AppSettings.self, from: record.json) else { continue }
            var changed = false
            for (old, keep) in mapping {
                guard let groups = settings.lockedGroups.removeValue(forKey: old.uuidString) else { continue }
                let merged = Set(settings.lockedGroups[keep.uuidString] ?? []).union(groups)
                settings.lockedGroups[keep.uuidString] = merged.sorted()
                changed = true
            }
            if changed { record.json = try JSONEncoder().encode(settings) }
        }
    }
}

/// Öffentliche Schnittstelle der Datenpflege (siehe `UserDataMaintenanceActor`).
public struct UserDataMaintenance: Sendable {
    private let actor: UserDataMaintenanceActor

    init(container: ModelContainer) {
        actor = UserDataMaintenanceActor(modelContainer: container)
    }

    @discardableResult
    public func migrateLegacyContentIDs() async throws -> Bool {
        try await actor.migrateLegacyContentIDs()
    }

    public func mergeDuplicateProfiles() async throws -> [UUID: UUID] {
        try await actor.mergeDuplicateProfiles()
    }

    public func plannedMerges() async throws -> [UUID: UUID] {
        try await actor.plannedMerges()
    }
}
