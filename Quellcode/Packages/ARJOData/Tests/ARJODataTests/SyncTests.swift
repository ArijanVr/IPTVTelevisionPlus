@testable import ARJOData
import ARJOCore
import SwiftData
import XCTest

/// Zwei Repositories mit verschiedenen Gerätekennungen auf demselben Speicher bilden zwei Geräte nach, deren
/// Daten CloudKit bereits zusammengeführt hat. Verspätete Uploads werden als direkt eingefügte Datensätze nachgestellt.
/// Echte CloudKit-Übertragung lässt sich so nicht prüfen; das bleibt ein Gerätetest.
final class ProgressSyncTests: XCTestCase {
    private var store: SwiftDataProfileRepository!
    private var appleTV: SwiftDataProgressRepository!
    private var iPhone: SwiftDataProgressRepository!
    private let profileID = UUID()
    private let movie = PlaybackTarget(kind: .movie, streamID: 7, title: "Heat")

    override func setUp() async throws {
        store = try SwiftDataProfileRepository(inMemory: true)
        try await store.save(Profile(id: profileID, name: "Quelle", kind: .xtream))
        appleTV = store.makeProgressRepository(deviceID: "apple-tv")
        iPhone = store.makeProgressRepository(deviceID: "iphone")
    }

    func testMovieStartedOnOneDeviceResumesOnAnother() async throws {
        try await appleTV.save(WatchProgress(target: movie, position: 2_605, duration: 6_000, watched: false), for: profileID)

        let onPhone = try await iPhone.progress(for: profileID, ids: [movie.id])[movie.id]
        XCTAssertEqual(onPhone?.position, 2_605, "43:25")
        XCTAssertEqual(onPhone?.duration, 6_000)
        let resumable = try await iPhone.continueWatching(for: profileID, limit: 10)
        XCTAssertEqual(resumable.map(\.id), [movie.id])
    }

    func testDelayedOlderUploadDoesNotOverwriteNewerPosition() async throws {
        let now = Date()
        try await iPhone.save(WatchProgress(target: movie, position: 3_000, duration: 6_000, watched: false, updatedAt: now), for: profileID)
        // Apple TV war offline: sein älterer Stand trifft erst jetzt ein.
        let context = ModelContext(store.container)
        context.insert(WatchProgressRecord(profileID: profileID, deviceID: "apple-tv", progress: WatchProgress(
            target: movie, position: 1_000, duration: 6_000, watched: false, updatedAt: now.addingTimeInterval(-600))))
        try context.save()

        let result = try await appleTV.progress(for: profileID, ids: [movie.id])[movie.id]
        XCTAssertEqual(result?.position, 3_000)
    }

    func testFreshActionWinsEvenIfOtherDeviceClockIsAhead() async throws {
        // Die Uhr des iPhones geht eine Stunde vor.
        let future = Date().addingTimeInterval(3_600)
        try await iPhone.save(WatchProgress(target: movie, position: 3_000, duration: 6_000, watched: false, updatedAt: future), for: profileID)
        // Danach spult man auf dem Apple TV bewusst zurück.
        try await appleTV.save(WatchProgress(target: movie, position: 120, duration: 6_000, watched: false), for: profileID)

        let result = try await iPhone.progress(for: profileID, ids: [movie.id])[movie.id]
        XCTAssertEqual(result?.position, 120, "Die zuletzt ausgeführte Aktion gewinnt")
        XCTAssertGreaterThan(result?.updatedAt ?? .distantPast, future)
    }

    func testRewatchingAWatchedMovieStartsFresh() async throws {
        try await appleTV.setWatched(true, target: movie, for: profileID)
        var current = try await iPhone.progress(for: profileID, ids: [movie.id])[movie.id]
        XCTAssertEqual(current?.watched, true)

        try await iPhone.save(WatchProgress(target: movie, position: 90, duration: 6_000, watched: false), for: profileID)
        current = try await appleTV.progress(for: profileID, ids: [movie.id])[movie.id]
        XCTAssertEqual(current?.watched, false)
        XCTAssertEqual(current?.position, 90)
    }

    func testManualWatchedDecisionBeatsOlderCloudUpdate() async throws {
        let now = Date()
        try await appleTV.setWatched(true, target: movie, for: profileID)
        let context = ModelContext(store.container)
        context.insert(WatchProgressRecord(profileID: profileID, deviceID: "ipad", progress: WatchProgress(
            target: movie, position: 2_000, duration: 6_000, watched: false, updatedAt: now.addingTimeInterval(-60))))
        try context.save()

        let result = try await iPhone.progress(for: profileID, ids: [movie.id])[movie.id]
        XCTAssertEqual(result?.watched, true)
    }

    func testEpisodesKeepTheirOwnProgress() async throws {
        let series = VODItem(kind: .series, sourceID: 50, name: "Show")
        let e4 = Episode(id: 104, seasonNumber: 2, episodeNumber: 4, title: "Vier").target(in: series)
        let e5 = Episode(id: 105, seasonNumber: 2, episodeNumber: 5, title: "Fünf").target(in: series)
        try await appleTV.save(WatchProgress(target: e4, position: 0, duration: 2_400, watched: true), for: profileID)
        try await iPhone.save(WatchProgress(target: e5, position: 600, duration: 2_400, watched: false), for: profileID)

        let both = try await appleTV.progress(for: profileID, ids: [e4.id, e5.id])
        XCTAssertEqual(both[e4.id]?.watched, true, "Episodenwechsel überschreibt keine andere Episode")
        XCTAssertEqual(both[e5.id]?.position, 600)
        XCTAssertEqual(both[e5.id]?.target.seasonNumber, 2)
        XCTAssertEqual(both[e5.id]?.target.episodeNumber, 5)
        let resumable = try await appleTV.continueWatching(for: profileID, limit: 10)
        XCTAssertEqual(resumable.map(\.id), [e5.id], "Pro Serie nur die zuletzt gesehene Episode")
    }

    func testClearedHistoryStaysClearedWhenOldRecordsArriveLate() async throws {
        try await appleTV.save(WatchProgress(target: movie, position: 500, duration: 6_000, watched: false), for: profileID)
        try await iPhone.deleteProgress(for: profileID)

        // Ein Gerät, das offline war, lädt seinen Stand von vor dem Löschen hoch.
        let context = ModelContext(store.container)
        context.insert(WatchProgressRecord(profileID: profileID, deviceID: "ipad", progress: WatchProgress(
            target: movie, position: 800, duration: 6_000, watched: false, updatedAt: Date().addingTimeInterval(-30))))
        try context.save()
        let afterClear = try await appleTV.allProgress(for: profileID)
        XCTAssertTrue(afterClear.isEmpty)

        try await appleTV.save(WatchProgress(target: movie, position: 42, duration: 6_000, watched: false), for: profileID)
        let afterNewPlayback = try await iPhone.progress(for: profileID, ids: [movie.id])[movie.id]
        XCTAssertEqual(afterNewPlayback?.position, 42, "Neue Wiedergabe nach dem Löschen zählt wieder")
    }

    func testLegacyRecordIsAdoptedInsteadOfDuplicated() async throws {
        let context = ModelContext(store.container)
        context.insert(WatchProgressRecord(profileID: profileID, deviceID: "", progress: WatchProgress(
            target: movie, position: 100, duration: 6_000, watched: false, updatedAt: Date().addingTimeInterval(-100))))
        try context.save()

        try await appleTV.save(WatchProgress(target: movie, position: 200, duration: 6_000, watched: false), for: profileID)

        let records = try ModelContext(store.container).fetch(FetchDescriptor<WatchProgressRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.deviceID, "apple-tv")
        XCTAssertEqual(records.first?.position, 200)
    }

    func testCorruptRecordsAreIgnored() async throws {
        let context = ModelContext(store.container)
        let broken = WatchProgressRecord(profileID: profileID, deviceID: "x", progress: WatchProgress(
            target: movie, position: 100, duration: 6_000, watched: false))
        broken.kindRawValue = "hologram"
        let mismatched = WatchProgressRecord(profileID: profileID, deviceID: "y", progress: WatchProgress(
            target: PlaybackTarget(kind: .movie, streamID: 8, title: "B"), position: 10, duration: 20, watched: false))
        mismatched.key = "movie-999"
        context.insert(broken)
        context.insert(mismatched)
        try context.save()

        let all = try await appleTV.allProgress(for: profileID)
        XCTAssertTrue(all.isEmpty)
    }

    func testStreamAddressIsNeverStored() async throws {
        let secret = URL(string: "http://host.example/movie/anna/geheim/7.mkv")!
        let target = PlaybackTarget(kind: .movie, streamID: 7, title: "Heat", directURL: secret)
        try await appleTV.save(WatchProgress(target: target, position: 100, duration: 6_000, watched: false), for: profileID)

        let records = try ModelContext(store.container).fetch(FetchDescriptor<WatchProgressRecord>())
        XCTAssertNil(records.first?.directURLString)
        let read = try await appleTV.progress(for: profileID, ids: [target.id])[target.id]
        XCTAssertNil(read?.target.directURL)
    }
}

final class LiveResumeStateTests: XCTestCase {
    func testNewChannelSwitchWinsOverFutureTimestampOfOtherDevice() async throws {
        let store = try SwiftDataProfileRepository(inMemory: true)
        let profile = Profile(name: "Q", kind: .xtream)
        try await store.save(profile)
        let future = Date().addingTimeInterval(3_600)
        try await store.setLiveResumeState(LiveResumeState(channelID: "1", updatedAt: future), for: profile.id)

        try await store.setLiveResumeState(LiveResumeState(channelID: "2", updatedAt: Date()), for: profile.id)

        let state = try await store.liveResumeState(for: profile.id)
        XCTAssertEqual(state?.channelID, "2")
        XCTAssertGreaterThan(state?.updatedAt ?? .distantPast, future)
    }

    func testTimeshiftInstantRoundTripsAndClears() async throws {
        let store = try SwiftDataProfileRepository(inMemory: true)
        let profile = Profile(name: "Q", kind: .xtream)
        try await store.save(profile)
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.setLiveResumeState(LiveResumeState(channelID: "5", timeshiftInstant: instant), for: profile.id)
        var state = try await store.liveResumeState(for: profile.id)
        XCTAssertEqual(state?.timeshiftInstant, instant)

        try await store.setLiveResumeState(nil, for: profile.id)
        state = try await store.liveResumeState(for: profile.id)
        XCTAssertNil(state)
    }
}

final class UserDataMaintenanceTests: XCTestCase {
    func testLegacyPlaylistIDsAreMigratedOnceAndWithoutSecrets() async throws {
        let store = try SwiftDataProfileRepository(inMemory: true)
        let profile = Profile(name: "M3U", kind: .m3u)
        try await store.save(profile)
        let channelURL = "http://host.example/live/anna/geheim/7.ts"
        let movieURL = URL(string: "http://host.example/movie/anna/geheim/99.mkv")!
        let legacyMovieID = ContentIdentity.stableHash(movieURL.absoluteString)

        let context = ModelContext(store.container)
        context.insert(PreferenceRecord(profileID: profile.id, preference: Preference(key: PreferenceKey.channel(channelURL), isFavorite: true)))
        context.insert(FolderRecord(profileID: profile.id, folder: ChannelFolder(name: "Sport", channelIDs: [channelURL, "42"]), sortIndex: 0))
        let record = WatchProgressRecord(profileID: profile.id, deviceID: "", progress: WatchProgress(
            target: PlaybackTarget(kind: .movie, streamID: legacyMovieID, title: "Film"), position: 300, duration: 6_000, watched: false))
        record.directURLString = movieURL.absoluteString
        context.insert(record)
        try context.save()
        try await store.setLiveResumeState(LiveResumeState(channelID: channelURL), for: profile.id)

        let maintenance = store.makeMaintenance()
        let changed = try await maintenance.migrateLegacyContentIDs()
        XCTAssertTrue(changed)

        let newChannelID = ContentIdentity.channelID(for: URL(string: channelURL)!)
        let organization = store.makeOrganizationRepository()
        let preferences = try await organization.preferences(for: profile.id)
        XCTAssertEqual(preferences[PreferenceKey.channel(newChannelID)]?.isFavorite, true)
        XCTAssertNil(preferences[PreferenceKey.channel(channelURL)])
        let folders = try await organization.folders(for: profile.id)
        XCTAssertEqual(folders.first?.channelIDs, [newChannelID, "42"])
        let live = try await store.liveResumeState(for: profile.id)
        XCTAssertEqual(live?.channelID, newChannelID)

        let newMovie = PlaybackTarget(kind: .movie, streamID: ContentIdentity.mediaID(for: movieURL), title: "Film")
        let progress = try await store.makeProgressRepository(deviceID: "a").progress(for: profile.id, ids: [newMovie.id])
        XCTAssertEqual(progress[newMovie.id]?.position, 300)
        let stored = try ModelContext(store.container).fetch(FetchDescriptor<WatchProgressRecord>())
        XCTAssertTrue(stored.allSatisfy { $0.directURLString == nil })

        let again = try await maintenance.migrateLegacyContentIDs()
        XCTAssertFalse(again, "Zweiter Lauf ändert nichts")
    }

    func testDuplicateProfilesOfSameSourceAreMergedDeterministically() async throws {
        let store = try SwiftDataProfileRepository(inMemory: true)
        let ids = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
        let keep = Profile(id: ids[0], name: "Server", kind: .xtream, sourceFingerprint: "fp")
        let duplicate = Profile(id: ids[1], name: "Server", kind: .xtream, sourceFingerprint: "fp")
        let unrelated = Profile(name: "Andere", kind: .xtream, sourceFingerprint: "other")
        for profile in [keep, duplicate, unrelated] { try await store.save(profile) }

        let tv = store.makeProgressRepository(deviceID: "tv")
        let movie = PlaybackTarget(kind: .movie, streamID: 1, title: "A")
        try await tv.save(WatchProgress(target: movie, position: 400, duration: 6_000, watched: false), for: duplicate.id)
        let organization = store.makeOrganizationRepository()
        try await organization.save(Preference(key: PreferenceKey.channel("9"), isFavorite: true), for: duplicate.id)
        try await store.setLiveResumeState(LiveResumeState(channelID: "9"), for: duplicate.id)
        let settings = store.makeSettingsRepository()
        var appSettings = AppSettings()
        appSettings.lockedGroups = [duplicate.id.uuidString: ["Erwachsene"]]
        try await settings.save(appSettings)

        let mapping = try await store.makeMaintenance().mergeDuplicateProfiles()
        XCTAssertEqual(mapping, [duplicate.id: keep.id])

        let remaining = try await store.profiles().map(\.id)
        XCTAssertEqual(Set(remaining), [keep.id, unrelated.id])
        let moved = try await tv.progress(for: keep.id, ids: [movie.id])[movie.id]
        XCTAssertEqual(moved?.position, 400)
        let favorites = try await organization.preferences(for: keep.id)
        XCTAssertEqual(favorites[PreferenceKey.channel("9")]?.isFavorite, true)
        let live = try await store.liveResumeState(for: keep.id)
        XCTAssertEqual(live?.channelID, "9")
        let loaded = try await settings.load()
        XCTAssertEqual(loaded.lockedGroups[keep.id.uuidString], ["Erwachsene"])
        XCTAssertNil(loaded.lockedGroups[duplicate.id.uuidString])

        let second = try await store.makeMaintenance().mergeDuplicateProfiles()
        XCTAssertTrue(second.isEmpty)
    }

    func testFingerprintIsStoredWithProfile() async throws {
        let store = try SwiftDataProfileRepository(inMemory: true)
        var profile = Profile(name: "S", kind: .xtream)
        try await store.save(profile)
        profile.sourceFingerprint = "abc"
        try await store.save(profile)
        let loaded = try await store.profiles()
        XCTAssertEqual(loaded.first?.sourceFingerprint, "abc")
        XCTAssertEqual(loaded.count, 1)
    }
}
