import ARJOCore
import Foundation
import SwiftData

/// Nutzerdaten (per CloudKit synchronisiert): alle Eigenschaften optional oder mit
/// Standardwert und ohne Eindeutigkeits-Constraints, wie CloudKit es verlangt.
/// Neue Felder nur optional hinzufügen, sonst bricht das CloudKit-Schema in Production.
@Model
final class ProfileRecord {
    var id: UUID = UUID()
    var name: String = ""
    var kindRawValue: String = ProfileKind.xtream.rawValue
    var createdAt: Date = Date.now
    var lastChannelID: String?
    /// `SourceFingerprint` der Quelle (SHA-256, ohne Zugangsdaten).
    var sourceFingerprint: String?
    /// Ereigniszeit des zuletzt gesehenen Senders.
    var lastChannelUpdatedAt: Date?
    /// Stelle einer laufenden Aufnahme/Timeshift als echte Uhrzeit; `nil` = live.
    var lastTimeshiftInstant: Date?
    /// Löschmarke des Wiedergabeverlaufs: ältere Einträge (auch verspätet hochgeladene) zählen nicht mehr.
    var progressClearedAt: Date?

    init(profile: Profile) {
        id = profile.id
        name = profile.name
        kindRawValue = profile.kind.rawValue
        sourceFingerprint = profile.sourceFingerprint
    }

    var profile: Profile? {
        ProfileKind(rawValue: kindRawValue).map { Profile(id: id, name: name, kind: $0, sourceFingerprint: sourceFingerprint) }
    }
}

@ModelActor
actor ProfileActor {
    func profiles() throws -> [Profile] {
        let descriptor = FetchDescriptor<ProfileRecord>(sortBy: [SortDescriptor(\.createdAt)])
        var seen = Set<UUID>()
        // Zwei Geräte können bei aktivem iCloud-Sync dasselbe Profil angelegt haben: nur das erste zählt.
        return try modelContext.fetch(descriptor).compactMap(\.profile).filter { seen.insert($0.id).inserted }
    }

    func save(_ profile: Profile) throws {
        if let record = try record(id: profile.id) {
            record.name = profile.name
            record.kindRawValue = profile.kind.rawValue
            if let fingerprint = profile.sourceFingerprint { record.sourceFingerprint = fingerprint }
        } else {
            modelContext.insert(ProfileRecord(profile: profile))
        }
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        try modelContext.delete(model: ProfileRecord.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }

    func liveResumeState(for profileID: UUID) throws -> LiveResumeState? {
        guard let record = try record(id: profileID), let channelID = record.lastChannelID else { return nil }
        return LiveResumeState(
            channelID: ContentIdentity.migratedChannelID(channelID),
            timeshiftInstant: record.lastTimeshiftInstant,
            updatedAt: record.lastChannelUpdatedAt ?? .distantPast
        )
    }

    /// Eine neue Aktion auf diesem Gerät liegt immer nach dem bekannten Stand (hybride Uhr): eine vorgehende
    /// Geräteuhr eines anderen Geräts kann den Senderwechsel hier nicht «älter» erscheinen lassen.
    /// Aufrufer schreiben nacheinander (Warteschlange), damit kein älterer Stand einen neueren überholt.
    func setLiveResumeState(_ state: LiveResumeState?, for profileID: UUID) throws {
        guard let record = try record(id: profileID) else { return }
        record.lastChannelID = state?.channelID
        record.lastTimeshiftInstant = state?.timeshiftInstant
        // Auch beim Löschen bleibt eine Ereigniszeit stehen, damit ein älterer Stand nicht als neuer gilt.
        record.lastChannelUpdatedAt = HybridTimestamp.next(now: state?.updatedAt ?? .now, after: record.lastChannelUpdatedAt)
        try modelContext.save()
    }

    private func record(id: UUID) throws -> ProfileRecord? {
        var descriptor = FetchDescriptor<ProfileRecord>(predicate: #Predicate { $0.id == id }, sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

/// Hält den Nutzerdaten-Speicher (Profile und Wiedergabestand teilen sich eine Datei).
/// Mit CloudKit liegt alles ausschliesslich in der privaten Datenbank des angemeldeten iCloud-Kontos.
public struct SwiftDataProfileRepository: ProfileRepository {
    private let actor: ProfileActor
    let container: ModelContainer

    /// - Parameter cloudKitContainer: Kennung des iCloud-Containers (z. B. `iCloud.ch.arjo.iptelevision`). Mit Wert werden Profile,
    ///   Einstellungen, Favoriten, Ordner und Wiedergabestand über CloudKit synchronisiert; das erfordert die
    ///   iCloud-Berechtigung der App. Ohne Wert bleibt alles lokal.
    public init(inMemory: Bool = false, cloudKitContainer: String? = nil) throws {
        let schema = Schema([ProfileRecord.self, WatchProgressRecord.self, SettingsRecord.self, PreferenceRecord.self, FolderRecord.self])
        let database: ModelConfiguration.CloudKitDatabase = cloudKitContainer.map { .private($0) } ?? .none
        let configuration = ModelConfiguration("UserData", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: database)
        container = try ModelContainer(for: schema, configurations: [configuration])
        actor = ProfileActor(modelContainer: container)
    }

    /// Wiedergabestand im selben Nutzerdaten-Speicher.
    /// - Parameter deviceID: Kennung dieser Installation; jedes Gerät schreibt eigene Einträge (siehe `ProgressRepository`).
    public func makeProgressRepository(deviceID: String = DeviceIdentity.current) -> SwiftDataProgressRepository {
        SwiftDataProgressRepository(container: container, deviceID: deviceID)
    }

    /// Migration älterer Kennungen und Zusammenführen doppelter Quellen nach dem ersten Abgleich.
    public func makeMaintenance() -> UserDataMaintenance {
        UserDataMaintenance(container: container)
    }

    /// Favoriten, Ordner, ausgeblendete und umbenannte Sender im selben Nutzerdaten-Speicher.
    public func makeOrganizationRepository() -> SwiftDataOrganizationRepository {
        SwiftDataOrganizationRepository(container: container)
    }

    /// Einstellungen im selben Nutzerdaten-Speicher.
    public func makeSettingsRepository() -> SwiftDataSettingsRepository {
        SwiftDataSettingsRepository(container: container)
    }

    public func profiles() async throws -> [Profile] { try await actor.profiles() }
    public func save(_ profile: Profile) async throws { try await actor.save(profile) }
    public func delete(id: UUID) async throws { try await actor.delete(id: id) }

    public func liveResumeState(for profileID: UUID) async throws -> LiveResumeState? {
        try await actor.liveResumeState(for: profileID)
    }

    public func setLiveResumeState(_ state: LiveResumeState?, for profileID: UUID) async throws {
        try await actor.setLiveResumeState(state, for: profileID)
    }
}

/// Kennung dieser Installation (nicht synchronisiert, keine Hardware-Kennung). Wird bei Neuinstallation neu erzeugt.
public enum DeviceIdentity {
    private static let key = "ch.arjo.iptelevision.deviceID"

    public static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: key)
        return created
    }
}

/// Ereigniszeit für Konfliktregeln: nie vor einem bereits bekannten Zeitpunkt, damit unterschiedliche Geräteuhren
/// die Reihenfolge bewusster Aktionen nicht umdrehen.
enum HybridTimestamp {
    static let tick: TimeInterval = 0.001

    static func next(now: Date, after known: Date?...) -> Date {
        known.compactMap { $0 }.reduce(now) { max($0, $1.addingTimeInterval(tick)) }
    }
}
