import ARJOCore
import ARJONetwork
import ARJOPlayer
import AVFoundation
import XCTest
@testable import ARJOUI

private let now = Date(timeIntervalSince1970: 1_792_859_400)

private func programme(_ channel: String, _ title: String, from offset: TimeInterval, minutes: Double) -> EPGProgramme {
    let start = now.addingTimeInterval(offset)
    return EPGProgramme(channelID: channel, start: start, stop: start.addingTimeInterval(minutes * 60), title: title)
}

@MainActor
final class EPGModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let catalog = FakeCatalog()
    private let repository = FakeEPG()
    private let provider = RecordingEPGProvider()
    private let store = InMemoryCredentialStore()

    override func setUp() {
        store.saved[profile.id] = .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))
        catalog.channelsByProfile[profile.id] = [
            Channel(id: "1", name: "SRF 1", source: .xtream(streamID: 1), epgChannelID: "srf1.ch"),
            Channel(id: "2", name: "Ohne EPG", source: .xtream(streamID: 2)),
        ]
    }

    private func makeModel() -> EPGModel {
        EPGModel(profile: profile, epg: repository, catalog: catalog, credentialStore: store,
                 makeProvider: { [provider] _ in provider }, clock: { now })
    }

    func testRefreshImportsWithCatalogIDsAndWindow() async {
        provider.programmes = [programme("srf1.ch", "Tagesschau", from: 0, minutes: 30)]
        let model = makeModel()

        await model.refresh()

        XCTAssertEqual(model.status, .idle)
        XCTAssertEqual(model.revision, 1)
        XCTAssertEqual(repository.programmesByProfile[profile.id]?.map(\.title), ["Tagesschau"])
        XCTAssertEqual(provider.requests.first?.ids, ["srf1.ch"])
        XCTAssertEqual(provider.requests.first?.window, DateInterval(start: now.addingTimeInterval(-6 * 3_600), end: now.addingTimeInterval(3 * 86_400)))
    }

    func testRefreshSkipsDownloadWhenCatalogHasNoEPGIDs() async {
        catalog.channelsByProfile[profile.id] = [Channel(id: "2", name: "X", source: .xtream(streamID: 2))]
        let model = makeModel()

        await model.refresh()

        XCTAssertEqual(model.status, .idle)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(model.revision, 0)
    }

    func testRefreshFailureShowsMessageAndKeepsOldGuide() async {
        repository.programmesByProfile[profile.id] = [programme("srf1.ch", "Alt", from: 0, minutes: 30)]
        provider.error = XtreamError.network(.timedOut)
        let model = makeModel()

        await model.refresh()

        XCTAssertEqual(model.status, .failed("Der Server antwortet nicht (Zeitüberschreitung)."))
        XCTAssertEqual(repository.programmesByProfile[profile.id]?.map(\.title), ["Alt"])
        model.dismissError()
        XCTAssertEqual(model.status, .idle)
    }

    func testRefreshIfNeededOnlyWhenStale() async {
        let model = makeModel()
        repository.updatedAt = now.addingTimeInterval(-3_600)
        await model.refreshIfNeeded()
        XCTAssertTrue(provider.requests.isEmpty)

        repository.updatedAt = now.addingTimeInterval(-7 * 3_600)
        await model.refreshIfNeeded()
        XCTAssertEqual(provider.requests.count, 1)

        repository.updatedAt = nil
        await model.refreshIfNeeded()
        XCTAssertEqual(provider.requests.count, 2)
    }

    func testLoadNowNextFillsAndClearsEntries() async {
        repository.programmesByProfile[profile.id] = [
            programme("srf1.ch", "Jetzt", from: -600, minutes: 30),
            programme("srf1.ch", "Danach", from: 1_200, minutes: 30),
        ]
        let model = makeModel()
        let channel = catalog.channelsByProfile[profile.id]![0]

        await model.loadNowNext(for: [channel])
        XCTAssertEqual(model.nowNext(for: channel)?.now?.title, "Jetzt")
        XCTAssertEqual(model.nowNext(for: channel)?.next?.title, "Danach")

        repository.programmesByProfile[profile.id] = []
        await model.loadNowNext(for: [channel])
        XCTAssertNil(model.nowNext(for: channel))
    }

    func testOffsetShiftsNowNextAndProgrammes() async throws {
        // Der Anbieter sendet 2 h früher als angezeigt: gespeichert ab jetzt-2h-10min, angezeigt ab jetzt-10min.
        let offset: TimeInterval = 2 * 3_600
        repository.programmesByProfile[profile.id] = [programme("srf1.ch", "Tagesschau", from: -offset - 600, minutes: 30)]
        let model = EPGModel(profile: profile, epg: repository, catalog: catalog, credentialStore: store,
                             makeProvider: { [provider] _ in provider }, clock: { now }, epgOffset: { offset })
        let channel = catalog.channelsByProfile[profile.id]![0]

        await model.loadNowNext(for: [channel])
        let shown = model.nowNext(for: channel)?.now
        XCTAssertEqual(shown?.title, "Tagesschau")
        XCTAssertEqual(shown?.start, now.addingTimeInterval(-600))

        let guide = try await model.programmes(for: [channel], from: now, to: now.addingTimeInterval(3_600))
        XCTAssertEqual(guide["srf1.ch"]?.first?.start, now.addingTimeInterval(-600))
    }

    func testOffsetChangedClearsNowNextAndBumpsRevision() async {
        repository.programmesByProfile[profile.id] = [programme("srf1.ch", "Jetzt", from: -600, minutes: 30)]
        let model = makeModel()
        let channel = catalog.channelsByProfile[profile.id]![0]
        await model.loadNowNext(for: [channel])
        XCTAssertNotNil(model.nowNext(for: channel))

        model.offsetChanged()

        XCTAssertNil(model.nowNext(for: channel))
        XCTAssertEqual(model.revision, 1)
    }

    func testM3UProfileUsesThePlaylistEPGAndToleratesPlaylistsWithoutOne() async {
        let url = URL(string: "http://provider.example/list.m3u")!
        store.saved[profile.id] = .m3uURL(url)
        let withEPG = StubPlaylistSource(epg: .success([programme("srf1.ch", "Aus Playlist", from: 0, minutes: 30)]))
        let model = EPGModel(profile: profile, epg: repository, catalog: catalog, credentialStore: store,
                             makeProvider: { [provider] _ in provider }, clock: { now },
                             makePlaylistProvider: { _ in withEPG })

        await model.refresh()
        XCTAssertEqual(model.status, .idle)
        XCTAssertEqual(repository.programmesByProfile[profile.id]?.map(\.title), ["Aus Playlist"])

        let withoutEPG = StubPlaylistSource(epg: .failure(M3UPlaylistError.noEPGSource))
        let quiet = EPGModel(profile: profile, epg: repository, catalog: catalog, credentialStore: store,
                             makeProvider: { [provider] _ in provider }, clock: { now },
                             makePlaylistProvider: { _ in withoutEPG })
        await quiet.refresh()
        XCTAssertEqual(quiet.status, .idle, "keine EPG-Adresse ist kein Fehler")
    }

    func testChannelWithoutEPGIDHasNoNowNext() async {
        let model = makeModel()
        let channel = catalog.channelsByProfile[profile.id]![1]
        await model.loadNowNext(for: [channel])
        XCTAssertNil(model.nowNext(for: channel))
    }
}

@MainActor
final class GuideViewModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let catalog = FakeCatalog()
    private let repository = FakeEPG()
    private let store = InMemoryCredentialStore()
    private let channels = [
        Channel(id: "1", name: "SRF 1", source: .xtream(streamID: 1), groupName: "Schweiz", epgChannelID: "srf1.ch"),
        Channel(id: "2", name: "SRF 2", source: .xtream(streamID: 2), groupName: "Schweiz", epgChannelID: "srf2.ch"),
        Channel(id: "3", name: "CNN", source: .xtream(streamID: 3), groupName: "News", epgChannelID: "cnn"),
    ]

    private func makeLive() async -> LiveTVViewModel {
        catalog.channelsByProfile[profile.id] = channels
        repository.updatedAt = now
        store.saved[profile.id] = .m3uURL(URL(string: "http://x.example/a.m3u")!)
        let hybrid = HybridPlaybackEngine(primary: FakeEngine(), fallback: nil, player: AVPlayer())
        let live = LiveTVViewModel(
            profile: profile, catalog: catalog, profiles: FakeProfiles(), credentialStore: store,
            makeProvider: { _ in StubProvider(result: .success([])) },
            playback: PlaybackController(engine: hybrid), engine: hybrid,
            epg: EPGModel(profile: profile, epg: repository, catalog: catalog, credentialStore: store,
                          makeProvider: { _ in RecordingEPGProvider() }, clock: { now })
        )
        await live.load()
        return live
    }

    func testLoadSelectsFirstGroupAndReadsProgrammesInWindow() async {
        repository.programmesByProfile[profile.id] = [
            programme("srf1.ch", "In Fenster", from: 600, minutes: 30),
            programme("srf1.ch", "Zu spät", from: 5 * 3_600, minutes: 30),
            programme("cnn", "Andere Gruppe", from: 600, minutes: 30),
        ]
        let live = await makeLive()
        let guide = GuideViewModel(live: live, clock: { now })

        await guide.load()

        XCTAssertEqual(guide.selectedGroup?.name, "Schweiz")
        XCTAssertEqual(guide.channels.map(\.id), ["1", "2"])
        XCTAssertEqual(guide.programmes(for: channels[0]).map(\.title), ["In Fenster"])
        XCTAssertTrue(guide.programmes(for: channels[1]).isEmpty)
    }

    func testWindowStartsHalfHourBeforeCurrentSlotAndShifts() async {
        let live = await makeLive()
        let guide = GuideViewModel(live: live, clock: { now })
        // 16:30 UTC → Slot 16:30, Fenster ab 16:00
        XCTAssertEqual(guide.windowStart, Date(timeIntervalSince1970: 1_792_857_600))
        XCTAssertEqual(guide.windowEnd.timeIntervalSince(guide.windowStart), 3 * 3_600)

        await guide.shiftWindow(hours: 3)
        XCTAssertEqual(guide.windowStart, Date(timeIntervalSince1970: 1_792_857_600 + 3 * 3_600))

        await guide.jumpToNow()
        XCTAssertEqual(guide.windowStart, Date(timeIntervalSince1970: 1_792_857_600))
    }

    func testGuideSkipsGroupsThatAreLocked() async {
        repository.programmesByProfile[profile.id] = [programme("cnn", "News", from: 600, minutes: 30)]
        let live = await makeLive()
        var locked: Set<String> = ["Schweiz"]
        let guide = GuideViewModel(live: live, clock: { now }, isAllowed: { !locked.contains($0.name) })

        await guide.load()
        XCTAssertEqual(guide.selectedGroup?.name, "News")
        XCTAssertEqual(guide.allowedGroups.map(\.name), ["News"])

        locked = ["Schweiz", "News"]
        await guide.load()
        XCTAssertNil(guide.selectedGroup)
        XCTAssertTrue(guide.channels.isEmpty)
    }

    func testSelectingAnotherGroupReloadsChannels() async {
        repository.programmesByProfile[profile.id] = [programme("cnn", "News", from: 600, minutes: 30)]
        let live = await makeLive()
        let guide = GuideViewModel(live: live, clock: { now })
        await guide.load()

        await guide.select(live.groups[1])

        XCTAssertEqual(guide.channels.map(\.id), ["3"])
        XCTAssertEqual(guide.programmes(for: channels[2]).map(\.title), ["News"])
    }
}
