import ARJOCore
import Foundation

public enum BackupError: Error, LocalizedError, Equatable {
    case unreadable
    case newerVersion

    public var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Die Datei ist kein gültiges IP Television+-Backup.")
        case .newerVersion: String(localized: "Das Backup stammt von einer neueren Version der App.")
        }
    }
}

public struct RestoreSummary: Equatable, Sendable {
    /// Quellen, deren Daten übernommen wurden.
    public var restoredProfiles: [String]
    /// Quellen aus dem Backup, die es auf diesem Gerät nicht gibt (Zugangsdaten sind nicht Teil des Backups).
    public var skippedProfiles: [String]
}

/// Sichert und stellt Einstellungen, Favoriten, Ordner und Wiedergabestand wieder her.
@MainActor
public final class BackupService {
    private let settings: SettingsModel
    private let profiles: any ProfileRepository
    private let organization: any OrganizationRepository
    private let progress: any ProgressRepository
    private let clock: () -> Date

    public init(
        settings: SettingsModel,
        profiles: any ProfileRepository,
        organization: any OrganizationRepository,
        progress: any ProgressRepository,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.settings = settings
        self.profiles = profiles
        self.organization = organization
        self.progress = progress
        self.clock = clock
    }

    public func makeBackup() async throws -> Data {
        var entries: [ProfileBackup] = []
        for profile in try await profiles.profiles() {
            entries.append(ProfileBackup(
                profile: profile,
                preferences: try await organization.preferences(for: profile.id).values.sorted { $0.key < $1.key },
                folders: try await organization.folders(for: profile.id),
                progress: try await progress.allProgress(for: profile.id)
            ))
        }
        let document = BackupDocument(createdAt: clock(), settings: settings.settings, profiles: entries)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Übernimmt Einstellungen und, für gleiche Quellen (gleiche ID, sonst gleicher Name und Typ), Favoriten,
    /// Ordner und Wiedergabestand. Beim Wiedergabestand gewinnt der neuere Eintrag.
    public func restore(from data: Data) async throws -> RestoreSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(BackupDocument.self, from: data) else { throw BackupError.unreadable }
        guard document.version <= BackupDocument.currentVersion else { throw BackupError.newerVersion }

        let local = try await profiles.profiles()
        var idMap: [UUID: UUID] = [:]
        var restored: [String] = []
        var skipped: [String] = []

        for entry in document.profiles {
            guard let match = local.first(where: { $0.id == entry.profile.id })
                ?? local.first(where: { $0.name == entry.profile.name && $0.kind == entry.profile.kind })
            else {
                skipped.append(entry.profile.name)
                continue
            }
            idMap[entry.profile.id] = match.id
            restored.append(match.name)
            try await restore(entry, into: match.id)
        }

        var newSettings = document.settings
        newSettings.lockedGroups = Dictionary(
            uniqueKeysWithValues: document.settings.lockedGroups.compactMap { key, groups in
                UUID(uuidString: key).flatMap { idMap[$0] }.map { ($0.uuidString, groups) }
            }
        )
        settings.settings = newSettings
        await settings.flush()
        return RestoreSummary(restoredProfiles: restored, skippedProfiles: skipped)
    }

    private func restore(_ entry: ProfileBackup, into profileID: UUID) async throws {
        for preference in entry.preferences { try await organization.save(preference, for: profileID) }
        for folder in entry.folders { try await organization.save(folder, for: profileID) }

        let existing = try await progress.progress(for: profileID, ids: entry.progress.map(\.id))
        for item in entry.progress where (existing[item.id]?.updatedAt ?? .distantPast) < item.updatedAt {
            try await progress.save(item, for: profileID)
        }
    }
}
