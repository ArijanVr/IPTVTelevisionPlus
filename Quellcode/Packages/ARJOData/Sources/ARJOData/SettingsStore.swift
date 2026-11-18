import ARJOCore
import Foundation
import SwiftData

/// Alle Einstellungen als ein JSON-Dokument: ein Datensatz lässt sich später einfach per CloudKit
/// synchronisieren und neue Felder brauchen keine Datenbank-Migration.
@Model
final class SettingsRecord {
    var key: String = ""
    var json: Data = Data()
    var updatedAt: Date = Date.now

    init(key: String, json: Data) {
        self.key = key
        self.json = json
    }
}

@ModelActor
actor SettingsActor {
    private static let key = "app"

    func load() throws -> AppSettings {
        guard let record = try records().first else { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: record.json)
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        let existing = try records()
        if let record = existing.first {
            record.json = data
            record.updatedAt = .now
            // Zwei Geräte können bei aktivem iCloud-Sync je einen Datensatz angelegt haben: Dubletten aufräumen.
            existing.dropFirst().forEach(modelContext.delete)
        } else {
            modelContext.insert(SettingsRecord(key: Self.key, json: data))
        }
        try modelContext.save()
    }

    /// Neuester Datensatz zuerst.
    private func records() throws -> [SettingsRecord] {
        let key = Self.key
        return try modelContext.fetch(FetchDescriptor<SettingsRecord>(
            predicate: #Predicate { $0.key == key },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }
}

public struct SwiftDataSettingsRepository: SettingsRepository {
    private let actor: SettingsActor

    init(container: ModelContainer) {
        actor = SettingsActor(modelContainer: container)
    }

    public func load() async throws -> AppSettings { try await actor.load() }
    public func save(_ settings: AppSettings) async throws { try await actor.save(settings) }
}
