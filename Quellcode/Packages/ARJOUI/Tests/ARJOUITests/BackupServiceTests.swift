import ARJOCore
import XCTest
@testable import ARJOUI

@MainActor
final class BackupServiceTests: XCTestCase {
    private let source = Profile(name: "example.com", kind: .xtream)
    private let profiles = FakeProfiles()
    private let progress = FakeProgress()
    private let organization = InMemoryOrganization()
    private lazy var settings = SettingsModel(repository: NullSettingsRepository(), debounce: .seconds(60))
    private let now = Date(timeIntervalSince1970: 1_792_859_400)

    private func makeService() -> BackupService {
        BackupService(settings: settings, profiles: profiles, organization: organization, progress: progress, clock: { [now] in now })
    }

    private let target = PlaybackTarget(kind: .movie, streamID: 1, title: "Heat", groupName: "Action")

    func testBackupContainsSettingsAndPerProfileData() async throws {
        profiles.stored = [source]
        settings.settings.accent = .blue
        organization.preferences[source.id] = [PreferenceKey.channel("7"): Preference(key: PreferenceKey.channel("7"), isFavorite: true)]
        organization.folders[source.id] = [ChannelFolder(name: "Sport", channelIDs: ["7"])]
        progress.stored[target.id] = WatchProgress(target: target, position: 300, duration: 6_000, watched: false, updatedAt: now)

        let data = try await makeService().makeBackup()
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.contains("\"Sport\""))
        XCTAssertFalse(text.lowercased().contains("password"), "keine Zugangsdaten im Backup")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(BackupDocument.self, from: data)
        XCTAssertEqual(document.version, BackupDocument.currentVersion)
        XCTAssertEqual(document.settings.accent, .blue)
        XCTAssertEqual(document.profiles.count, 1)
        XCTAssertEqual(document.profiles[0].progress.map(\.id), [target.id])
    }

    func testRestoreMatchesByIDThenByNameAndRemapsLockedGroups() async throws {
        // Backup von einem anderen Gerät: gleiche Quelle (Name/Typ), aber andere Profil-ID.
        let backupProfile = Profile(name: "example.com", kind: .xtream)
        let unknown = Profile(name: "anderer-anbieter.ch", kind: .xtream)
        var backupSettings = AppSettings()
        backupSettings.epgOffsetMinutes = 60
        backupSettings.lockedGroups = [backupProfile.id.uuidString: ["live:Erwachsene"], unknown.id.uuidString: ["live:X"]]
        let document = BackupDocument(createdAt: now, settings: backupSettings, profiles: [
            ProfileBackup(profile: backupProfile,
                          preferences: [Preference(key: PreferenceKey.channel("7"), isFavorite: true)],
                          folders: [ChannelFolder(name: "Sport")],
                          progress: [WatchProgress(target: target, position: 900, duration: 6_000, watched: false, updatedAt: now)]),
            ProfileBackup(profile: unknown, preferences: [], folders: [], progress: []),
        ])
        profiles.stored = [source]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let summary = try await makeService().restore(from: try encoder.encode(document))

        XCTAssertEqual(summary, RestoreSummary(restoredProfiles: ["example.com"], skippedProfiles: ["anderer-anbieter.ch"]))
        XCTAssertEqual(organization.preferences[source.id]?[PreferenceKey.channel("7")]?.isFavorite, true)
        XCTAssertEqual(organization.folders[source.id]?.map(\.name), ["Sport"])
        XCTAssertEqual(progress.stored[target.id]?.position, 900)
        XCTAssertEqual(settings.settings.epgOffsetMinutes, 60)
        XCTAssertEqual(settings.settings.lockedGroups, [source.id.uuidString: ["live:Erwachsene"]])
    }

    func testRestoreKeepsNewerLocalProgress() async throws {
        profiles.stored = [source]
        progress.stored[target.id] = WatchProgress(target: target, position: 5_000, duration: 6_000, watched: false, updatedAt: now.addingTimeInterval(100))
        let document = BackupDocument(createdAt: now, settings: AppSettings(), profiles: [
            ProfileBackup(profile: source, preferences: [], folders: [], progress: [
                WatchProgress(target: target, position: 10, duration: 6_000, watched: false, updatedAt: now),
            ]),
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        _ = try await makeService().restore(from: try encoder.encode(document))

        XCTAssertEqual(progress.stored[target.id]?.position, 5_000)
    }

    func testRejectsGarbageAndNewerVersions() async throws {
        let service = makeService()
        do {
            _ = try await service.restore(from: Data("kein json".utf8))
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? BackupError, .unreadable)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let future = BackupDocument(version: BackupDocument.currentVersion + 1, settings: AppSettings(), profiles: [])
        do {
            _ = try await service.restore(from: try encoder.encode(future))
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? BackupError, .newerVersion)
        }
    }
}

final class InMemoryOrganization: OrganizationRepository, @unchecked Sendable {
    var preferences: [UUID: [String: Preference]] = [:]
    var folders: [UUID: [ChannelFolder]] = [:]

    func preferences(for profileID: UUID) async throws -> [String: Preference] { preferences[profileID] ?? [:] }
    func save(_ preference: Preference, for profileID: UUID) async throws { preferences[profileID, default: [:]][preference.key] = preference }
    func setFavoriteOrder(_ channelIDs: [String], for profileID: UUID) async throws {}
    func folders(for profileID: UUID) async throws -> [ChannelFolder] { folders[profileID] ?? [] }
    func save(_ folder: ChannelFolder, for profileID: UUID) async throws {
        var list = folders[profileID] ?? []
        if let index = list.firstIndex(where: { $0.id == folder.id }) { list[index] = folder } else { list.append(folder) }
        folders[profileID] = list
    }
    func deleteFolder(id: UUID, for profileID: UUID) async throws { folders[profileID]?.removeAll { $0.id == id } }
    func deleteOrganization(for profileID: UUID) async throws { preferences[profileID] = nil; folders[profileID] = nil }
}
