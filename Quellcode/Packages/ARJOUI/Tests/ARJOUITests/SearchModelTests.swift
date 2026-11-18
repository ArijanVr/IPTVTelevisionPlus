import ARJOCore
import XCTest
@testable import ARJOUI

@MainActor
final class SearchModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let catalog = FakeCatalog()
    private let vod = FakeVOD()
    private let epg = FakeEPG()
    private let now = Date(timeIntervalSince1970: 1_792_859_400)

    private let channels = [
        Channel(id: "1", name: "SRF 1", source: .xtream(streamID: 1), epgChannelID: "srf1.ch"),
        Channel(id: "2", name: "Dark Channel", source: .xtream(streamID: 2), epgChannelID: "dark"),
    ]

    override func setUp() {
        catalog.channelsByProfile[profile.id] = channels
        vod.itemsByKind[.movie] = [VODItem(kind: .movie, sourceID: 1, name: "Dark Knight"), VODItem(kind: .movie, sourceID: 2, name: "Alien")]
        vod.itemsByKind[.series] = [VODItem(kind: .series, sourceID: 9, name: "Dark")]
        func programme(_ channel: String, _ title: String, from offset: TimeInterval) -> EPGProgramme {
            EPGProgramme(channelID: channel, start: now.addingTimeInterval(offset), stop: now.addingTimeInterval(offset + 1_800), title: title)
        }
        epg.programmesByProfile[profile.id] = [
            programme("srf1.ch", "Dark Tales", from: -600),
            programme("srf1.ch", "Dark Tales Spezial", from: 4 * 3_600),
            programme("srf1.ch", "Dark vorbei", from: -7_200),
            programme("unbekannt", "Dark ohne Sender", from: 600),
            programme("dark", "Wetter", from: 600),
        ]
    }

    private func makeModel() -> SearchModel {
        SearchModel(profile: profile, catalog: catalog, vod: vod, epg: epg, clock: { [now] in now })
    }

    func testCombinesAllSourcesAndDropsProgrammesWithoutChannel() async {
        let model = makeModel()
        model.query = "  dark "

        await model.search()

        XCTAssertEqual(model.state, .done)
        XCTAssertNil(model.warning)
        XCTAssertEqual(model.results.channels.map(\.id), ["2"])
        XCTAssertEqual(model.results.movies.map(\.name), ["Dark Knight"])
        XCTAssertEqual(model.results.series.map(\.name), ["Dark"])
        XCTAssertEqual(model.results.programmes.map(\.programme.title), ["Dark Tales", "Dark Tales Spezial"])
        XCTAssertEqual(model.results.programmes.map(\.channel.id), ["1", "1"])
    }

    func testEPGOffsetShiftsSearchWindowAndResults() async {
        let offset: TimeInterval = 3_600
        let model = SearchModel(profile: profile, catalog: catalog, vod: vod, epg: epg, clock: { [now] in now }, epgOffset: { offset })
        model.query = "Wetter"

        await model.search()

        // Gespeichert: +600 s; angezeigt mit Versatz +1 h: +4200 s.
        XCTAssertEqual(model.results.programmes.map(\.programme.start), [now.addingTimeInterval(600 + offset)])
    }

    func testLockedGroupsNeverAppearInResults() async {
        catalog.channelsByProfile[profile.id] = [
            Channel(id: "1", name: "Dark Late", source: .xtream(streamID: 1), groupName: "Erwachsene", epgChannelID: "x"),
            Channel(id: "2", name: "Dark News", source: .xtream(streamID: 2), groupName: "News", epgChannelID: "y"),
        ]
        vod.itemsByKind[.movie] = [
            VODItem(kind: .movie, sourceID: 1, name: "Dark Film", groupName: "FSK 18"),
            VODItem(kind: .movie, sourceID: 2, name: "Dark Komödie", groupName: "Komödie"),
        ]
        epg.programmesByProfile[profile.id] = [
            EPGProgramme(channelID: "x", start: now, stop: now.addingTimeInterval(600), title: "Dark Show"),
            EPGProgramme(channelID: "y", start: now, stop: now.addingTimeInterval(600), title: "Dark Magazin"),
        ]
        let model = SearchModel(profile: profile, catalog: catalog, vod: vod, epg: epg, clock: { [now] in now },
                                isLocked: { area, group in (area == .live && group == "Erwachsene") || (area == .movie && group == "FSK 18") })
        model.query = "dark"

        await model.search()

        XCTAssertEqual(model.results.channels.map(\.id), ["2"])
        XCTAssertEqual(model.results.movies.map(\.name), ["Dark Komödie"])
        XCTAssertEqual(model.results.programmes.map(\.programme.title), ["Dark Magazin"])
    }

    func testTooShortQueryClearsResultsWithoutSearching() async {
        let model = makeModel()
        model.query = "dark"
        await model.search()
        XCTAssertFalse(model.results.isEmpty)

        model.query = "d"
        await model.search()

        XCTAssertTrue(model.isQueryTooShort)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.state, .idle)
    }

    func testNoMatchesIsDoneAndEmpty() async {
        let model = makeModel()
        model.query = "xyzxyz"
        await model.search()
        XCTAssertEqual(model.state, .done)
        XCTAssertTrue(model.results.isEmpty)
    }

    func testOneFailingSourceKeepsOthersAndWarns() async {
        catalog.searchError = URLError(.cannotOpenFile)
        let model = makeModel()
        model.query = "dark"

        await model.search()

        XCTAssertEqual(model.warning, "Einige Ergebnisse konnten nicht geladen werden.")
        XCTAssertTrue(model.results.channels.isEmpty)
        XCTAssertEqual(model.results.movies.map(\.name), ["Dark Knight"])
        XCTAssertEqual(model.state, .done)
    }

    func testIgnoresAccentsAndCase() async {
        vod.itemsByKind[.movie] = [VODItem(kind: .movie, sourceID: 3, name: "Amélie")]
        let model = makeModel()
        model.query = "AMELIE"
        await model.search()
        XCTAssertEqual(model.results.movies.map(\.name), ["Amélie"])
    }

    func testRecentQueriesAreDeduplicatedNewestFirstAndPersisted() {
        let defaults = UserDefaults(suiteName: "SearchModelTests-\(UUID())")!
        let model = SearchModel(profile: profile, catalog: catalog, vod: vod, epg: epg, history: defaults)
        for term in ["Dark", "Wetter", "dark", "x"] {
            model.query = term
            model.rememberQuery()
        }
        XCTAssertEqual(model.recentQueries, ["dark", "Wetter"], "zu kurze Begriffe zählen nicht, Gross-/Kleinschreibung wird zusammengeführt")

        let reloaded = SearchModel(profile: profile, catalog: catalog, vod: vod, epg: epg, history: defaults)
        XCTAssertEqual(reloaded.recentQueries, ["dark", "Wetter"])

        reloaded.clearRecentQueries()
        XCTAssertTrue(SearchModel(profile: profile, catalog: catalog, vod: vod, epg: epg, history: defaults).recentQueries.isEmpty)
    }
}
