import ARJOCore
import ARJONetwork
import ARJOPlayer
import AVFoundation
import XCTest
@testable import ARJOUI

/// Wann der Player speichert (lokal zuerst, gedrosselt, sofort bei Pause/Spulen/Hintergrund) und wie Playlist-
/// Adressen ohne gespeicherte Stream-Adresse gefunden werden.
@MainActor
final class ProgressSavingTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let store = InMemoryCredentialStore()
    private let progress = FakeProgress()
    private let engine = FakeEngine()
    private lazy var hybrid = HybridPlaybackEngine(primary: engine, fallback: nil, player: AVPlayer())
    private let movie = PlaybackTarget(kind: .movie, streamID: 501, containerExtension: "mkv", title: "Heat")
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        store.saved[profile.id] = .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))
    }

    private func makeModel(profile: Profile? = nil, resolve: @escaping (PlaybackTarget) async -> URL? = { _ in nil }) -> VODPlayerModel {
        VODPlayerModel(
            profile: profile ?? self.profile, credentialStore: store, progress: progress,
            playback: PlaybackController(engine: hybrid, policy: ReconnectPolicy(stallTimeout: nil), sleep: { _ in }),
            engine: hybrid, clock: { [unowned self] in now }, resolveDirectURL: resolve
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, line: UInt = #line) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "Bedingung wurde nicht erreicht", line: line)
    }

    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    func testPeriodicProgressIsThrottledButPauseAndSeekSaveImmediately() async {
        let model = makeModel()
        await model.play(movie)
        engine.emit(.playing)

        engine.emit(.progress(position: 600, duration: 6_000))
        await waitUntil { self.progress.saved.count == 1 }

        now += 5
        engine.emit(.progress(position: 605, duration: 6_000))
        await settle()
        XCTAssertEqual(progress.saved.count, 1, "Nicht jede Meldung führt zu einem Schreibvorgang")

        now += 1
        engine.emit(.checkpoint(position: 1_200, duration: 6_000))
        await waitUntil { self.progress.saved.count == 2 }
        XCTAssertEqual(progress.saved.last?.position, 1_200, "Spulen/Pause speichert sofort")

        now += VODPlayerModel.periodicSaveInterval
        engine.emit(.progress(position: 1_230, duration: 6_000))
        await waitUntil { self.progress.saved.count == 3 }
        XCTAssertEqual(progress.saved.last?.position, 1_230)
        model.close()
    }

    func testBackgroundSavesLatestPositionAtOnce() async {
        let model = makeModel()
        await model.play(movie)
        engine.emit(.playing)
        engine.emit(.progress(position: 600, duration: 6_000))
        await waitUntil { self.progress.saved.count == 1 }
        now += 5
        engine.emit(.progress(position: 605, duration: 6_000))
        await settle()

        model.persistPending()
        await waitUntil { self.progress.saved.count == 2 }
        XCTAssertEqual(progress.saved.last?.position, 605)

        model.close()
        await settle()
        XCTAssertEqual(progress.saved.count, 2, "Nichts doppelt speichern")
    }

    func testSwitchingEpisodeSavesThePreviousOneFirst() async {
        let series = VODItem(kind: .series, sourceID: 9, name: "Show")
        let first = Episode(id: 1, seasonNumber: 1, episodeNumber: 1, title: "Eins").target(in: series)
        let second = Episode(id: 2, seasonNumber: 1, episodeNumber: 2, title: "Zwei").target(in: series)
        let model = makeModel()
        await model.play(first)
        engine.emit(.playing)
        engine.emit(.progress(position: 100, duration: 2_400))
        await waitUntil { self.progress.saved.count == 1 }
        now += 5
        engine.emit(.progress(position: 110, duration: 2_400))
        await settle()

        await model.play(second)
        await waitUntil { self.progress.saved.count == 2 }
        XCTAssertEqual(progress.saved.last?.id, first.id)
        XCTAssertEqual(progress.saved.last?.position, 110)
        model.close()
    }

    func testPlaylistTitleFromContinueWatchingFindsItsAddressInTheCatalog() async {
        let playlistProfile = Profile(name: "Liste", kind: .m3u)
        store.saved[playlistProfile.id] = .m3uURL(URL(string: "http://list.example/get.php?username=a&password=b")!)
        let address = URL(string: "http://list.example/movie/a/b/501.mkv")!
        let model = makeModel(profile: playlistProfile, resolve: { $0.streamID == 501 ? address : nil })

        await model.play(movie)
        XCTAssertEqual(engine.loadedURLs, [address])

        engine.emit(.playing)
        engine.emit(.progress(position: 600, duration: 6_000))
        await waitUntil { self.progress.saved.count == 1 }
        XCTAssertNil(progress.saved.first?.target.directURL, "Die Adresse (mit Zugangsdaten) wird nicht gespeichert")
        model.close()
    }

    func testClearHistoryDeletesProgressAndRefreshesLists() async {
        let model = makeModel()
        let revision = model.progressRevision
        await model.clearHistory()
        XCTAssertEqual(progress.deleted, [profile.id])
        XCTAssertGreaterThan(model.progressRevision, revision)
    }
}

/// Live TV über Geräte: derselbe Sender, bei Timeshift die gespeicherte Stelle, wenn sie noch im Archiv liegt.
@MainActor
final class LiveResumeTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let catalog = FakeCatalog()
    private let profiles = FakeProfiles()
    private let store = InMemoryCredentialStore()
    private let engine = FakeEngine()
    private lazy var hybrid = HybridPlaybackEngine(primary: engine, fallback: nil, player: AVPlayer())
    private let now = Date(timeIntervalSince1970: 1_792_859_400)
    private let archived = Channel(id: "1", name: "SRF 1", source: .xtream(streamID: 1), groupName: "Schweiz", archiveDays: 2)
    private let plain = Channel(id: "2", name: "SRF 2", source: .xtream(streamID: 2), groupName: "Schweiz")

    override func setUp() {
        store.saved[profile.id] = .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))
    }

    private func makeModel() -> LiveTVViewModel {
        LiveTVViewModel(
            profile: profile, catalog: catalog, profiles: profiles, credentialStore: store,
            makeProvider: { [archived, plain] _ in StubProvider(result: .success([archived, plain])) },
            playback: PlaybackController(engine: hybrid), engine: hybrid,
            epg: EPGModel(profile: profile, epg: FakeEPG(), catalog: catalog, credentialStore: store,
                          makeProvider: { _ in RecordingEPGProvider() }, epgOffset: { 0 }),
            clock: { [now] in now }
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, line: UInt = #line) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "Bedingung wurde nicht erreicht", line: line)
    }

    func testResumesTimeshiftPositionFromOtherDeviceInsideArchive() async {
        let instant = now.addingTimeInterval(-3_600)
        profiles.liveStates[profile.id] = LiveResumeState(channelID: "1", timeshiftInstant: instant)
        let model = makeModel()
        await model.load()

        await model.resumeLastChannel()

        XCTAssertEqual(model.nowPlaying, archived)
        XCTAssertNotNil(model.catchupProgramme)
        XCTAssertTrue(engine.loadedURLs.last?.path.hasPrefix("/timeshift/") == true, "\(engine.loadedURLs)")
    }

    func testExpiredTimeshiftPositionOpensLive() async {
        profiles.liveStates[profile.id] = LiveResumeState(channelID: "1", timeshiftInstant: now.addingTimeInterval(-3 * 86_400))
        let model = makeModel()
        await model.load()

        await model.resumeLastChannel()

        XCTAssertNil(model.catchupProgramme)
        XCTAssertTrue(engine.loadedURLs.last?.path.hasPrefix("/live/") == true, "\(engine.loadedURLs)")
    }

    func testChannelWithoutArchiveNeverInventsTimeshift() async {
        profiles.liveStates[profile.id] = LiveResumeState(channelID: "2", timeshiftInstant: now.addingTimeInterval(-600))
        let model = makeModel()
        await model.load()

        await model.resumeLastChannel()

        XCTAssertEqual(model.nowPlaying, plain)
        XCTAssertNil(model.catchupProgramme)
        XCTAssertFalse(model.canResumeTimeshift(on: plain, at: now.addingTimeInterval(-600)))
    }

    func testTimeshiftPositionIsSavedOnPauseAndClearedWhenGoingLive() async {
        let model = makeModel()
        await model.load()
        let programme = EPGProgramme(channelID: "1", start: now.addingTimeInterval(-1_800), stop: now.addingTimeInterval(1_800), title: "News")
        await model.playCatchup(programme, on: archived)
        engine.emit(.playing)

        engine.emit(.checkpoint(position: 120, duration: 3_600))
        await waitUntil { self.profiles.liveStates[self.profile.id]?.timeshiftInstant == programme.start.addingTimeInterval(120) }

        model.goLive()
        await waitUntil { self.profiles.liveStates[self.profile.id]?.timeshiftInstant == nil }
        XCTAssertEqual(profiles.liveStates[profile.id]?.channelID, "1")
    }

    func testClearHistoryIsNotUndoneByPendingChannelSave() async {
        let model = makeModel()
        await model.load()
        model.play(plain, in: [archived, plain])
        await model.clearHistory()
        for _ in 0..<200 { await Task.yield() }
        XCTAssertNil(profiles.liveStates[profile.id])
        XCTAssertNil(model.lastChannel)
    }

    func testChannelSwitchIsRememberedForOtherDevices() async {
        let model = makeModel()
        await model.load()
        model.play(plain, in: [archived, plain])
        await waitUntil { self.profiles.liveStates[self.profile.id]?.channelID == "2" }
        XCTAssertNil(profiles.liveStates[profile.id]?.timeshiftInstant)
    }
}

/// Dieselbe Quelle auf mehreren Geräten ergibt ein Profil: Zusammenführen und Wiederverwenden beim Anmelden.
@MainActor
final class ProfileReconcileTests: XCTestCase {
    private let profiles = FakeProfiles()
    private let store = InMemoryCredentialStore()
    private let active = FakeActiveProfile()
    private let credentials = SourceCredentials.xtream(XtreamCredentials(
        serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))

    func testMergedDuplicateMovesCredentialsAndActiveProfile() async {
        let keep = Profile(name: "A", kind: .xtream, sourceFingerprint: "fp")
        let old = UUID()
        profiles.stored = [keep]
        store.saved[old] = credentials
        active.id = old
        var cleaned: [UUID] = []
        let model = AppModel(
            profiles: profiles, activeProfile: active, credentialStore: store, cleanups: [],
            localCleanups: [{ cleaned.append($0) }],
            merging: ProfileMerging(planned: { [old: keep.id] }, merge: { [old: keep.id] })
        )

        await model.bootstrap()

        XCTAssertEqual(model.phase, .live(keep))
        XCTAssertEqual(active.id, keep.id)
        XCTAssertEqual(store.saved[keep.id], credentials)
        XCTAssertNil(store.saved[old])
        XCTAssertEqual(cleaned, [old])
    }

    func testFailedCredentialCopyLeavesDuplicateUntouched() async {
        let keep = Profile(name: "A", kind: .xtream, sourceFingerprint: "fp")
        let old = UUID()
        profiles.stored = [keep]
        store.saved[old] = credentials
        store.failOnSave = true
        active.id = old
        let merged = MergeFlag()
        let model = AppModel(
            profiles: profiles, activeProfile: active, credentialStore: store, cleanups: [],
            merging: ProfileMerging(planned: { [old: keep.id] }, merge: { merged.set(); return [old: keep.id] })
        )

        await model.bootstrap()

        XCTAssertFalse(merged.value, "Ohne kopierte Zugangsdaten wird nicht zusammengeführt")
        XCTAssertEqual(store.saved[old], credentials, "Zugangsdaten bleiben erreichbar")
    }

    func testUnreadableCredentialsStopTheMerge() async {
        let keep = Profile(name: "A", kind: .xtream, sourceFingerprint: "fp")
        let old = UUID()
        profiles.stored = [keep]
        active.id = old
        let failing = FailingLoadCredentialStore()
        let merged = MergeFlag()
        let model = AppModel(
            profiles: profiles, activeProfile: active, credentialStore: failing, cleanups: [],
            merging: ProfileMerging(planned: { [old: keep.id] }, merge: { merged.set(); return [old: keep.id] })
        )

        await model.bootstrap()

        XCTAssertFalse(merged.value, "Ein Keychain-Lesefehler darf nicht wie «keine Zugangsdaten» behandelt werden")
    }

    func testMissingFingerprintIsAddedFromLocalCredentials() async {
        let profile = Profile(name: "A", kind: .xtream)
        profiles.stored = [profile]
        store.saved[profile.id] = credentials
        let model = AppModel(profiles: profiles, activeProfile: active, credentialStore: store, cleanups: [])

        await model.bootstrap()

        XCTAssertEqual(profiles.stored.first?.sourceFingerprint, SourceFingerprint.make(for: credentials))
        guard case .live(let current) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(current.id, profile.id)
    }

    func testRenamedProfileFromOtherDeviceKeepsSession() async {
        let profile = Profile(name: "A", kind: .xtream)
        profiles.stored = [profile]
        let model = AppModel(profiles: profiles, activeProfile: active, credentialStore: store, cleanups: [])
        await model.bootstrap()

        var renamed = profile
        renamed.name = "Wohnzimmer"
        profiles.stored = [renamed]
        await model.refreshProfiles()

        XCTAssertEqual(model.phase, .live(renamed))
    }

    func testSigningInWithKnownSourceReusesSyncedProfile() async {
        let synced = Profile(name: "Server", kind: .xtream, sourceFingerprint: SourceFingerprint.make(for: credentials))
        profiles.stored = [synced]
        let login = LoginViewModel(
            makeClient: { _ in AcceptingAuthenticator() },
            credentialStore: store, profileRepository: profiles,
            validatePlaylist: { _ in }, importPlaylistFile: nil, onSignedIn: { _ in }
        )
        login.server = "example.com:8080"
        login.username = "anna"
        login.password = "anderes-geraet"

        await login.signIn()

        guard case .succeeded(let profile) = login.state else { return XCTFail("\(login.state)") }
        XCTAssertEqual(profile.id, synced.id)
        XCTAssertEqual(profiles.stored.count, 1)
        XCTAssertNotNil(store.saved[synced.id])
    }
}

private struct AcceptingAuthenticator: XtreamAuthenticating {
    func authenticate() async throws -> XtreamAccountInfo { XtreamAccountInfo(username: "anna", status: "Active") }
}

private final class MergeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private struct FailingLoadCredentialStore: CredentialStore {
    func save(_ credentials: SourceCredentials, for profileID: UUID) throws {}
    func load(for profileID: UUID) throws -> SourceCredentials? { throw URLError(.cannotOpenFile) }
    func delete(for profileID: UUID) throws {}
}
