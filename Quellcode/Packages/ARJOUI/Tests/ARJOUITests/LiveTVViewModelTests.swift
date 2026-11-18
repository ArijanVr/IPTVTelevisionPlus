import ARJOCore
import ARJONetwork
import ARJOPlayer
import AVFoundation
import XCTest
@testable import ARJOUI

@MainActor
final class LiveTVViewModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let catalog = FakeCatalog()
    private let profiles = FakeProfiles()
    private let store = InMemoryCredentialStore()
    private let engine = FakeEngine()
    private lazy var hybrid = HybridPlaybackEngine(primary: engine, fallback: nil, player: AVPlayer())
    private let epgRepository = FakeEPG()
    private let epgProvider = RecordingEPGProvider()
    private let credentials = XtreamCredentials(
        serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim")

    private let channels = [
        Channel(id: "1", name: "SRF 1", source: .xtream(streamID: 1), groupName: "Schweiz"),
        Channel(id: "2", name: "SRF 2", source: .xtream(streamID: 2), groupName: "Schweiz"),
        Channel(id: "3", name: "CNN", source: .xtream(streamID: 3), groupName: "News"),
    ]

    override func setUp() {
        store.saved[profile.id] = .xtream(credentials)
    }

    private func makeModel(provider: Result<[Channel], Error>? = nil, resumes: Bool = false, autoRefresh: Bool = false, playlist: [Channel]? = nil, epgOffset: TimeInterval = 0, serverTimeZone: TimeZone? = nil) -> LiveTVViewModel {
        let result = provider ?? .success(channels)
        return LiveTVViewModel(
            profile: profile, catalog: catalog, profiles: profiles, credentialStore: store,
            makeProvider: { _ in StubProvider(result: result) },
            playback: PlaybackController(engine: hybrid), engine: hybrid,
            epg: EPGModel(profile: profile, epg: epgRepository, catalog: catalog, credentialStore: store,
                          makeProvider: { [epgProvider] _ in epgProvider }, epgOffset: { epgOffset }),
            resumesOnLaunch: { resumes },
            refreshesAutomatically: { autoRefresh },
            clock: { Date(timeIntervalSince1970: 1_792_859_400) },
            makePlaylistSource: playlist.map { list in { _ in StubPlaylistSource(channels: list) } },
            serverTimeZone: { _ in serverTimeZone }
        )
    }

    func testLoadImportsWhenCatalogIsEmpty() async {
        let model = makeModel()
        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.groups, [ChannelGroup(name: "Schweiz", channelCount: 2), ChannelGroup(name: "News", channelCount: 1)])
        XCTAssertEqual(catalog.importCount, 1)
    }

    func testLoadSkipsImportWhenCatalogExists() async {
        catalog.channelsByProfile[profile.id] = channels
        let model = makeModel(provider: .failure(XtreamError.unexpectedResponse))

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(catalog.importCount, 0)
    }

    func testLoadFailureShowsReadableMessage() async {
        let model = makeModel(provider: .failure(XtreamError.invalidCredentials))
        await model.load()
        XCTAssertEqual(model.phase, .failed("Benutzername oder Passwort sind falsch."))
    }

    func testRefreshFailureKeepsCatalogAndReportsError() async {
        catalog.channelsByProfile[profile.id] = channels
        let model = makeModel(provider: .failure(XtreamError.network(.timedOut)))
        await model.load()

        await model.refreshCatalog()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.groups.count, 2)
        XCTAssertEqual(model.refreshError, "Der Server antwortet nicht (Zeitüberschreitung).")
    }

    func testM3UProfileImportsItsChannelsFromThePlaylist() async {
        let url = URL(string: "http://provider.example/list.m3u?token=abc")!
        store.saved[profile.id] = .m3uURL(url)
        let model = makeModel(playlist: [Channel(id: url.absoluteString + "#1", name: "Arte", source: .url(URL(string: "http://cdn.example/arte.m3u8")!), groupName: "Kultur")])

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.groups, [ChannelGroup(name: "Kultur", channelCount: 1)])
    }

    func testM3UChannelPlaysItsOwnURLWithoutXtreamCredentials() async {
        let direct = URL(string: "http://cdn.example/arte.m3u8?token=1")!
        store.saved[profile.id] = .m3uURL(URL(string: "http://provider.example/list.m3u")!)
        let channel = Channel(id: "a", name: "Arte", source: .url(direct))
        let model = makeModel(playlist: [channel])
        await model.load()

        model.play(channel, in: [channel])

        XCTAssertEqual(engine.loadedURLs, [direct])
    }

    func testM3UProfileWithoutPlaylistSourceReportsUnsupported() async {
        store.saved[profile.id] = .m3uURL(URL(string: "http://x.example/a.m3u")!)
        let model = makeModel()
        await model.load()
        XCTAssertEqual(model.phase, .failed("Diese Quelle enthält keine Filme und Serien."))
    }

    func testPlayBuildsStreamURLFromKeychainAndRemembersChannel() async {
        let model = makeModel()
        await model.load()

        model.play(channels[0], in: channels)

        XCTAssertEqual(engine.loadedURLs.map(\.absoluteString), ["http://example.com:8080/live/anna/geheim/1.m3u8"])
        XCTAssertEqual(model.nowPlaying, channels[0])
        XCTAssertTrue(model.isPlayerPresented)
        for _ in 0..<50 where profiles.lastChannels[profile.id] == nil { await Task.yield() }
        XCTAssertEqual(profiles.lastChannels[profile.id], "1")
    }

    func testPlayAdjacentWrapsAroundTheQueue() async {
        let model = makeModel()
        await model.load()
        model.play(channels[2], in: channels)

        model.playAdjacent(offset: 1)
        XCTAssertEqual(model.nowPlaying, channels[0])

        model.playAdjacent(offset: -1)
        XCTAssertEqual(model.nowPlaying, channels[2])
    }

    func testClosePlayerStopsPlayback() async {
        let model = makeModel()
        await model.load()
        model.play(channels[0], in: channels)

        model.closePlayer()

        XCTAssertFalse(model.isPlayerPresented)
        XCTAssertNil(model.nowPlaying)
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(model.playback.status, .idle)
    }

    func testRestoresLastChannelOnLoad() async {
        catalog.channelsByProfile[profile.id] = channels
        profiles.lastChannels[profile.id] = "3"
        let model = makeModel()

        await model.load()

        XCTAssertEqual(model.lastChannel, channels[2])
    }

    func testStartPlaysChannelOneOrLastChannelDependingOnSetting() async {
        catalog.channelsByProfile[profile.id] = channels
        profiles.lastChannels[profile.id] = "2"

        let off = makeModel(resumes: false)
        await off.start()
        XCTAssertTrue(off.isPlayerPresented)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["1.m3u8"])

        await off.clearHistory()
        profiles.lastChannels[profile.id] = "2"
        let on = makeModel(resumes: true)
        await on.start()
        XCTAssertTrue(on.isPlayerPresented)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["1.m3u8", "2.m3u8"])

        on.closePlayer()
        await on.start()
        XCTAssertFalse(on.isPlayerPresented)
    }

    func testStartSkipsIneligibleGroups() async {
        catalog.channelsByProfile[profile.id] = channels
        let model = makeModel()
        model.eligibleGroups = { $0.filter { $0.name == "News" } }
        await model.start()
        XCTAssertEqual(model.nowPlaying?.id, "3")
    }

    func testSwitchGroupStartsFirstChannelOfNextGroupAndWraps() async throws {
        catalog.channelsByProfile[profile.id] = channels
        let model = makeModel()
        await model.start()
        XCTAssertEqual(model.nowPlaying?.id, "1")

        model.switchGroup(by: 1)
        XCTAssertEqual(model.groupBanner, .init(name: "News", position: 2, count: 2))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.nowPlaying?.id, "3")

        model.switchGroup(by: 1)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.nowPlaying?.id, "1")
    }

    func testRapidGroupSwitchesStartOnlyLastGroup() async throws {
        catalog.channelsByProfile[profile.id] = channels
        let model = makeModel()
        await model.start()
        let before = engine.loadedURLs.count
        model.switchGroup(by: 1)
        model.switchGroup(by: 1)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.nowPlaying?.id, "1")
        XCTAssertEqual(engine.loadedURLs.count, before + 1)
    }

    func testDigitEntryJumpsGloballyAndUnknownNumberShowsMessage() async {
        var numbered = channels
        for i in numbered.indices { numbered[i].number = i + 1 }
        catalog.channelsByProfile[profile.id] = numbered
        let model = makeModel()
        await model.start()

        model.enterDigit(3)
        XCTAssertEqual(model.numberEntry, "3")
        await model.commitNumber()
        XCTAssertEqual(model.nowPlaying?.id, "3")
        XCTAssertEqual(model.numberEntry, "")

        model.enterDigit(9); model.enterDigit(9)
        await model.commitNumber()
        XCTAssertEqual(model.nowPlaying?.id, "3")
        XCTAssertNotNil(model.numberMessage)

        model.recallPreviousChannel()
        XCTAssertEqual(model.nowPlaying?.id, "1")
    }

    func testCancelNumberClearsEntry() async {
        catalog.channelsByProfile[profile.id] = channels
        let model = makeModel()
        model.enterDigit(4)
        model.cancelNumber()
        XCTAssertEqual(model.numberEntry, "")
    }

    func testStartRefreshesStaleCatalogOnlyWhenAutoRefreshIsOn() async {
        catalog.channelsByProfile[profile.id] = channels
        let now = Date(timeIntervalSince1970: 1_792_859_400)

        catalog.updatedAt = now.addingTimeInterval(-3_600)
        await makeModel(autoRefresh: true).start()
        XCTAssertEqual(catalog.importCount, 0, "frisch: kein Neuladen")

        catalog.updatedAt = now.addingTimeInterval(-25 * 3_600)
        await makeModel(autoRefresh: false).start()
        XCTAssertEqual(catalog.importCount, 0, "Auto-Aktualisierung aus")

        await makeModel(autoRefresh: true).start()
        XCTAssertEqual(catalog.importCount, 1, "veraltet: Neuladen")
    }

    private let now = Date(timeIntervalSince1970: 1_792_859_400) // 16:30 UTC
    private func archived(_ days: Int?) -> Channel {
        Channel(id: "1", name: "SRF 1", source: .xtream(streamID: 1), groupName: "Schweiz", archiveDays: days)
    }

    private func programme(startingAt offset: TimeInterval, minutes: Double = 60) -> EPGProgramme {
        let start = now.addingTimeInterval(offset)
        return EPGProgramme(channelID: "srf1.ch", start: start, stop: start.addingTimeInterval(minutes * 60), title: "Tagesschau")
    }

    func testCatchUpIsOnlyOfferedForStartedProgrammesInsideTheArchiveWindow() {
        let model = makeModel()
        XCTAssertTrue(model.canCatchUp(archived(3), programme: programme(startingAt: -600)), "läuft gerade")
        XCTAssertTrue(model.canCatchUp(archived(3), programme: programme(startingAt: -2 * 86_400)))
        XCTAssertFalse(model.canCatchUp(archived(3), programme: programme(startingAt: -4 * 86_400)), "älter als das Archiv")
        XCTAssertFalse(model.canCatchUp(archived(3), programme: programme(startingAt: 600)), "noch nicht begonnen")
        XCTAssertFalse(model.canCatchUp(archived(nil), programme: programme(startingAt: -600)))
        XCTAssertFalse(model.canCatchUp(archived(0), programme: programme(startingAt: -600)))
    }

    func testPlayCatchupBuildsTimeshiftURLInServerTimeAndRemovesTheEPGOffset() async {
        // Angezeigt 16:00–17:00 mit EPG-Versatz +1 h → beim Anbieter 15:00 UTC = 17:00 in Zürich (Sommerzeit).
        let model = makeModel(epgOffset: 3_600, serverTimeZone: TimeZone(identifier: "Europe/Zurich"))
        let channel = archived(3)
        let shown = programme(startingAt: -1_800)

        await model.playCatchup(shown, on: channel)

        XCTAssertEqual(engine.loadedURLs.map(\.absoluteString),
                       ["http://example.com:8080/timeshift/anna/geheim/60/2026-10-24%3A17-00/1.m3u8"])
        XCTAssertEqual(model.catchupProgramme, shown)
        XCTAssertEqual(model.nowPlaying, channel)
        XCTAssertTrue(model.isPlayerPresented)
    }

    func testGoLiveAndNewChannelLeaveCatchupMode() async {
        let model = makeModel()
        let channel = archived(3)
        await model.playCatchup(programme(startingAt: -600), on: channel)
        XCTAssertNotNil(model.catchupProgramme)

        model.goLive()
        XCTAssertNil(model.catchupProgramme)
        XCTAssertEqual(engine.loadedURLs.last?.lastPathComponent, "1.m3u8")
        XCTAssertFalse(engine.loadedURLs.last?.absoluteString.contains("timeshift") ?? true)

        await model.playCatchup(programme(startingAt: -600), on: channel)
        model.play(channel, in: [channel])
        XCTAssertNil(model.catchupProgramme)
    }

    func testCatchupWithoutArchiveDoesNothing() async {
        let model = makeModel()
        await model.playCatchup(programme(startingAt: -600), on: archived(nil))
        XCTAssertTrue(engine.loadedURLs.isEmpty)
        XCTAssertFalse(model.isPlayerPresented)
    }

    func testCloseLeavesCatchupMode() async {
        let model = makeModel()
        await model.playCatchup(programme(startingAt: -600), on: archived(2))
        model.closePlayer()
        XCTAssertNil(model.catchupProgramme)
    }

    func testConcurrentLoadsImportOnlyOnce() async {
        let model = makeModel()
        async let first: Void = model.load()
        async let second: Void = model.start()
        _ = await (first, second)
        XCTAssertEqual(catalog.importCount, 1)
    }

    func testMissingCredentialsDuringPlaybackEndsInFailedState() async {
        let model = makeModel()
        await model.load()
        store.saved[profile.id] = nil

        model.play(channels[0], in: channels)

        XCTAssertEqual(model.playback.status, .failed("Die Stream-Adresse konnte nicht ermittelt werden."))
    }
}
