import ARJOCore
import Foundation
import SwiftData

/// Wiedergabestand (per CloudKit synchronisiert): alle Eigenschaften mit Standardwert oder optional,
/// ohne Eindeutigkeits-Constraints. Eindeutig ist `profileID` + `key` + `deviceID`: jedes Gerät schreibt nur
/// seinen eigenen Eintrag, damit ein verspäteter Upload nie den Stand eines anderen Geräts überschreibt.
@Model
final class WatchProgressRecord {
    var profileID: UUID = UUID()
    var key: String = ""
    /// Installation, die den Eintrag schreibt; leer bei Einträgen älterer Versionen (werden beim nächsten Speichern übernommen).
    var deviceID: String = ""
    var kindRawValue: String = PlaybackTarget.Kind.movie.rawValue
    var streamID: Int = 0
    var containerExtension: String = PlaybackTarget.defaultExtension
    var title: String = ""
    var subtitle: String?
    var posterURLString: String?
    var seriesID: Int?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var groupName: String?
    var seriesName: String?
    /// Nur noch von älteren Versionen gefüllt: Playlist-Adressen können Zugangsdaten enthalten und gehören
    /// nicht in die iCloud-Datenbank. Wird bei der Migration geleert.
    var directURLString: String?
    var position: Double = 0
    var duration: Double = 0
    var watched: Bool = false
    /// Ereigniszeit (hybride Uhr, siehe `ProgressRepository`).
    var updatedAt: Date = Date.now

    init(profileID: UUID, deviceID: String, progress: WatchProgress) {
        self.profileID = profileID
        self.deviceID = deviceID
        key = progress.id
        apply(progress)
    }

    func apply(_ progress: WatchProgress) {
        let target = progress.target
        key = target.id
        kindRawValue = target.kind.rawValue
        streamID = target.streamID
        containerExtension = target.containerExtension
        title = target.title
        subtitle = target.subtitle
        posterURLString = target.posterURL?.absoluteString
        seriesID = target.seriesID
        seasonNumber = target.seasonNumber
        episodeNumber = target.episodeNumber
        groupName = target.groupName
        seriesName = target.seriesName
        directURLString = nil
        position = progress.position.isFinite ? max(progress.position, 0) : 0
        duration = progress.duration.isFinite ? max(progress.duration, 0) : 0
        watched = progress.watched
        updatedAt = progress.updatedAt
    }

    /// `nil` bei beschädigten oder unvollständigen Einträgen (z. B. aus einer neueren Version).
    var progress: WatchProgress? {
        guard let kind = PlaybackTarget.Kind(rawValue: kindRawValue), !key.isEmpty, key == "\(kind.rawValue)-\(streamID)" else {
            return nil
        }
        return WatchProgress(
            target: PlaybackTarget(
                kind: kind, streamID: streamID, containerExtension: containerExtension, title: title,
                subtitle: subtitle, posterURL: posterURLString.flatMap { URL(string: $0) }, seriesID: seriesID,
                groupName: groupName, seriesName: seriesName, seasonNumber: seasonNumber, episodeNumber: episodeNumber
            ),
            position: position, duration: duration, watched: watched, updatedAt: updatedAt
        )
    }

    /// Reihenfolge der Konfliktregel: neuere Ereigniszeit gewinnt, bei Gleichstand entscheidet die Gerätekennung,
    /// damit alle Geräte denselben Gewinner wählen.
    static func isNewer(_ lhs: WatchProgressRecord, than rhs: WatchProgressRecord) -> Bool {
        (lhs.updatedAt, lhs.deviceID) > (rhs.updatedAt, rhs.deviceID)
    }
}

@ModelActor
actor ProgressActor {
    /// Unter dieser Position gilt ein Eintrag nicht als «angefangen».
    private static let startedThreshold: TimeInterval = 10

    func progress(for profileID: UUID, ids: [String]) throws -> [String: WatchProgress] {
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.profileID == profileID && ids.contains($0.key) }
        )
        return Dictionary(uniqueKeysWithValues: try winners(in: modelContext.fetch(descriptor), profileID: profileID).map { ($0.id, $0) })
    }

    func allProgress(for profileID: UUID) throws -> [WatchProgress] {
        try winners(in: records(profileID: profileID), profileID: profileID).sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ progress: WatchProgress, for profileID: UUID, deviceID: String) throws {
        let key = progress.id
        let existing = try records(profileID: profileID, key: key)
        var entry = progress
        entry.updatedAt = HybridTimestamp.next(
            now: progress.updatedAt, after: existing.map(\.updatedAt).max(), try clearedAt(profileID)
        )
        if let own = existing.first(where: { $0.deviceID == deviceID }) {
            own.apply(entry)
        } else if let legacy = existing.first(where: { $0.deviceID.isEmpty }) {
            // Eintrag einer älteren Version: übernehmen statt verdoppeln.
            legacy.deviceID = deviceID
            legacy.apply(entry)
        } else {
            modelContext.insert(WatchProgressRecord(profileID: profileID, deviceID: deviceID, progress: entry))
        }
        try modelContext.save()
    }

    func continueWatching(for profileID: UUID, limit: Int) throws -> [WatchProgress] {
        let started = try winners(in: records(profileID: profileID), profileID: profileID)
            .filter { !$0.watched && $0.position > Self.startedThreshold }
            .sorted { $0.updatedAt > $1.updatedAt }
        var seenSeries = Set<Int>()
        var result: [WatchProgress] = []
        for progress in started {
            if let seriesID = progress.target.seriesID, !seenSeries.insert(seriesID).inserted { continue }
            result.append(progress)
            if result.count == limit { break }
        }
        return result
    }

    func setWatched(_ watched: Bool, target: PlaybackTarget, for profileID: UUID, deviceID: String) throws {
        let duration = try progress(for: profileID, ids: [target.id])[target.id]?.duration ?? 0
        try save(WatchProgress(target: target, position: 0, duration: duration, watched: watched), for: profileID, deviceID: deviceID)
    }

    /// Löscht den Verlauf und setzt eine Löschmarke, damit Einträge anderer Geräte, die noch nicht hochgeladen waren,
    /// nicht zurückkommen.
    func deleteProgress(for profileID: UUID) throws {
        try modelContext.delete(model: WatchProgressRecord.self, where: #Predicate { $0.profileID == profileID })
        let profiles = try modelContext.fetch(FetchDescriptor<ProfileRecord>(predicate: #Predicate { $0.id == profileID }))
        let mark = HybridTimestamp.next(now: .now, after: profiles.compactMap(\.progressClearedAt).max())
        profiles.forEach { $0.progressClearedAt = mark }
        try modelContext.save()
    }

    // MARK: Konfliktregel

    /// Pro Inhalt der neueste Eintrag aller Geräte; Einträge vor der Löschmarke und beschädigte Einträge zählen nicht.
    private func winners(in records: [WatchProgressRecord], profileID: UUID) throws -> [WatchProgress] {
        let cleared = try clearedAt(profileID) ?? .distantPast
        var best: [String: WatchProgressRecord] = [:]
        for record in records where record.updatedAt > cleared && record.progress != nil {
            if let current = best[record.key], !WatchProgressRecord.isNewer(record, than: current) { continue }
            best[record.key] = record
        }
        return best.values.compactMap(\.progress)
    }

    private func clearedAt(_ profileID: UUID) throws -> Date? {
        try modelContext.fetch(FetchDescriptor<ProfileRecord>(predicate: #Predicate { $0.id == profileID }))
            .compactMap(\.progressClearedAt).max()
    }

    private func records(profileID: UUID) throws -> [WatchProgressRecord] {
        try modelContext.fetch(FetchDescriptor<WatchProgressRecord>(predicate: #Predicate { $0.profileID == profileID }))
    }

    private func records(profileID: UUID, key: String) throws -> [WatchProgressRecord] {
        try modelContext.fetch(FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.profileID == profileID && $0.key == key }
        ))
    }
}

public struct SwiftDataProgressRepository: ProgressRepository {
    private let actor: ProgressActor
    private let deviceID: String

    init(container: ModelContainer, deviceID: String) {
        actor = ProgressActor(modelContainer: container)
        self.deviceID = deviceID
    }

    public func progress(for profileID: UUID, ids: [String]) async throws -> [String: WatchProgress] {
        try await actor.progress(for: profileID, ids: ids)
    }

    public func allProgress(for profileID: UUID) async throws -> [WatchProgress] {
        try await actor.allProgress(for: profileID)
    }

    public func save(_ progress: WatchProgress, for profileID: UUID) async throws {
        try await actor.save(progress, for: profileID, deviceID: deviceID)
    }

    public func continueWatching(for profileID: UUID, limit: Int) async throws -> [WatchProgress] {
        try await actor.continueWatching(for: profileID, limit: limit)
    }

    public func setWatched(_ watched: Bool, target: PlaybackTarget, for profileID: UUID) async throws {
        try await actor.setWatched(watched, target: target, for: profileID, deviceID: deviceID)
    }

    public func deleteProgress(for profileID: UUID) async throws {
        try await actor.deleteProgress(for: profileID)
    }
}
