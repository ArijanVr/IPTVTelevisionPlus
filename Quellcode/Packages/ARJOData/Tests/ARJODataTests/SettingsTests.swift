import ARJOCore
import XCTest
@testable import ARJOData

final class SettingsRepositoryTests: XCTestCase {
    func testDefaultsWhenNothingSaved() async throws {
        let repository = try SwiftDataProfileRepository(inMemory: true).makeSettingsRepository()
        let settings = try await repository.load()
        XCTAssertEqual(settings, AppSettings())
    }

    func testSaveReplacesAndRoundTripsAllFields() async throws {
        let repository = try SwiftDataProfileRepository(inMemory: true).makeSettingsRepository()
        var settings = AppSettings()
        settings.accent = .blue
        settings.epgOffsetMinutes = -90
        settings.timeZoneID = "Europe/Zurich"
        settings.bufferSeconds = 8
        settings.aspect = .fill
        settings.resumeLastChannelOnLaunch = true
        settings.autoRefresh = false
        settings.lockedGroups = ["abc": ["live:Erwachsene"]]
        settings.showsChannelNames = false
        settings.tileSize = .large
        settings.homeOrder = [.favorites, .hero] + HomeSection.allCases.filter { $0 != .favorites && $0 != .hero }
        settings.hiddenHomeSections = [.movies, .onAir]

        try await repository.save(AppSettings())
        try await repository.save(settings)

        let loaded = try await repository.load()
        XCTAssertEqual(loaded, settings)
    }

    func testFormerGoldAccentBecomesMonochrome() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"accent":"gold"}"#.utf8))
        XCTAssertEqual(decoded.accent, .mono)
        XCTAssertEqual(AppSettings().accent, .mono)
    }

    func testHomeLayoutSkipsUnknownSectionsAndAppendsMissingOnes() throws {
        let json = #"{"homeOrder":["series","zukunft","favorites","series"],"hiddenHomeSections":["hero","zukunft"],"tileSize":"riesig"}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(Array(decoded.homeOrder.prefix(2)), [.series, .favorites])
        XCTAssertEqual(Set(decoded.homeOrder), Set(HomeSection.allCases), "fehlende Reihen hinten angehängt")
        XCTAssertEqual(decoded.homeOrder.count, HomeSection.allCases.count, "keine Doppelten")
        XCTAssertEqual(decoded.hiddenHomeSections, [.hero])
        XCTAssertEqual(decoded.tileSize, .regular, "unbekannte Grösse fällt auf den Standard zurück")
        XCTAssertEqual(decoded.visibleHomeSections.first, .series)
        XCTAssertFalse(decoded.visibleHomeSections.contains(.hero))
    }

    func testOlderDocumentsWithMissingFieldsStillDecode() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"accent":"green","unbekannt":1}"#.utf8))
        XCTAssertEqual(decoded.accent, .green)
        XCTAssertEqual(decoded.bufferSeconds, AppSettings().bufferSeconds)
        XCTAssertTrue(decoded.showsChannelNames)
        XCTAssertEqual(decoded.visibleHomeSections, HomeSection.allCases)
        XCTAssertTrue(decoded.autoRefresh)
    }
}

final class KeychainPINStoreTests: XCTestCase {
    func testSetVerifyAndRemove() throws {
        let store = KeychainPINStore(service: "ch.arjo.iptelevision.tests.pin.\(UUID())", synchronizable: false)
        defer { try? store.removePIN() }

        do {
            XCTAssertFalse(try store.hasPIN)
            try store.setPIN("1234")
        } catch KeychainError.unexpectedStatus(let status) where status == errSecMissingEntitlement || status == errSecInteractionNotAllowed {
            throw XCTSkip("Keychain in dieser Umgebung nicht nutzbar (OSStatus \(status)).")
        }

        XCTAssertTrue(try store.hasPIN)
        XCTAssertTrue(try store.verify("1234"))
        XCTAssertFalse(try store.verify("1235"))

        try store.setPIN("999999")
        XCTAssertFalse(try store.verify("1234"))
        XCTAssertTrue(try store.verify("999999"))

        try store.removePIN()
        XCTAssertFalse(try store.hasPIN)
        XCTAssertFalse(try store.verify("999999"))
    }
}

import SwiftData

final class SyncConflictTests: XCTestCase {
    func testNewestSettingsRecordWinsAndDuplicatesAreCleanedOnSave() async throws {
        let profiles = try SwiftDataProfileRepository(inMemory: true)
        let context = ModelContext(profiles.container)
        var old = AppSettings(); old.accent = .red
        var new = AppSettings(); new.accent = .blue
        let oldRecord = SettingsRecord(key: "app", json: try JSONEncoder().encode(old))
        oldRecord.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newRecord = SettingsRecord(key: "app", json: try JSONEncoder().encode(new))
        newRecord.updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(oldRecord)
        context.insert(newRecord)
        try context.save()

        let repository = profiles.makeSettingsRepository()
        let loaded = try await repository.load()
        XCTAssertEqual(loaded.accent, .blue)

        try await repository.save(new)
        let remaining = try ModelContext(profiles.container).fetch(FetchDescriptor<SettingsRecord>())
        XCTAssertEqual(remaining.count, 1)
    }

    func testDuplicateProfilesAreListedOnce() async throws {
        let profiles = try SwiftDataProfileRepository(inMemory: true)
        let profile = Profile(name: "A", kind: .xtream)
        let context = ModelContext(profiles.container)
        context.insert(ProfileRecord(profile: profile))
        context.insert(ProfileRecord(profile: profile))
        try context.save()

        let listed = try await profiles.profiles()
        XCTAssertEqual(listed, [profile])
    }

    func testNewestProgressWinsAndAllProgressListsEverything() async throws {
        let profiles = try SwiftDataProfileRepository(inMemory: true)
        let progress = profiles.makeProgressRepository()
        let profileID = UUID()
        let target = PlaybackTarget(kind: .movie, streamID: 1, title: "Heat")
        let other = PlaybackTarget(kind: .movie, streamID: 2, title: "Alien")

        let context = ModelContext(profiles.container)
        context.insert(WatchProgressRecord(profileID: profileID, deviceID: "", progress: WatchProgress(
            target: target, position: 100, duration: 6_000, watched: false, updatedAt: Date(timeIntervalSince1970: 1_000))))
        context.insert(WatchProgressRecord(profileID: profileID, deviceID: "", progress: WatchProgress(
            target: target, position: 900, duration: 6_000, watched: false, updatedAt: Date(timeIntervalSince1970: 2_000))))
        try context.save()
        try await progress.save(WatchProgress(target: other, position: 5, duration: 10, watched: true), for: profileID)

        let one = try await progress.progress(for: profileID, ids: [target.id])
        let all = try await progress.allProgress(for: profileID)
        XCTAssertEqual(one[target.id]?.position, 900)
        XCTAssertEqual(Set(all.map(\.id)), [target.id, other.id])
        XCTAssertEqual(all.count, 2, "Dubletten zählen nur einmal")
        XCTAssertEqual(all.first { $0.id == target.id }?.position, 900)
    }
}

final class TopShelfStoreTests: XCTestCase {
    func testWriteAndReadRoundTripAndMissingFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("topshelf-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TopShelfStore(fileURL: file)
        XCTAssertNil(try store.read())

        let snapshot = TopShelfSnapshot(
            items: [TopShelfItem(id: "movie-1", title: "Heat", subtitle: nil, imageURL: URL(string: "http://img.example/h.jpg"),
                                 progress: 0.25, deepLink: DeepLink.play(itemID: "movie-1"))],
            updatedAt: Date(timeIntervalSince1970: 1_792_859_400)
        )
        try store.write(snapshot)
        XCTAssertEqual(try store.read(), snapshot)
    }
}
