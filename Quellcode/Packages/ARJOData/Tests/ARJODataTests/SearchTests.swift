import ARJOCore
import XCTest
@testable import ARJOData

final class SearchRepositoryTests: XCTestCase {
    private let profileID = UUID()
    private let now = Date(timeIntervalSince1970: 1_792_859_400)

    func testSearchChannelsIgnoresCaseAndAccentsAndKeepsListOrder() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([
            Channel(id: "1", name: "SRF 1 HD", source: .xtream(streamID: 1)),
            Channel(id: "2", name: "RTS Un", source: .xtream(streamID: 2)),
            Channel(id: "3", name: "Télévision Suisse", source: .xtream(streamID: 3)),
            Channel(id: "4", name: "srf zwei", source: .xtream(streamID: 4)),
        ]))

        let srf = try await repository.searchChannels(for: profileID, query: "SRF", limit: 10)
        let tele = try await repository.searchChannels(for: profileID, query: "television", limit: 10)
        let limited = try await repository.searchChannels(for: profileID, query: "srf", limit: 1)
        let none = try await repository.searchChannels(for: profileID, query: "xyz", limit: 10)

        XCTAssertEqual(srf.map(\.id), ["1", "4"])
        XCTAssertEqual(tele.map(\.id), ["3"])
        XCTAssertEqual(limited.map(\.id), ["1"])
        XCTAssertTrue(none.isEmpty)
    }

    func testSearchChannelsOnlySeesCurrentCatalogOfThatProfile() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([Channel(id: "1", name: "Alt Sender", source: .xtream(streamID: 1))]))
        try await repository.importChannels(for: profileID, from: .from([Channel(id: "2", name: "Neu Sender", source: .xtream(streamID: 2))]))
        try await repository.importChannels(for: UUID(), from: .from([Channel(id: "3", name: "Fremd Sender", source: .xtream(streamID: 3))]))

        let result = try await repository.searchChannels(for: profileID, query: "Sender", limit: 10)
        XCTAssertEqual(result.map(\.id), ["2"])
    }

    func testChannelsForEPGIDsPicksFirstChannelPerID() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([
            Channel(id: "1", name: "SRF 1", source: .xtream(streamID: 1), epgChannelID: "srf1.ch"),
            Channel(id: "2", name: "SRF 1 HD", source: .xtream(streamID: 2), epgChannelID: "srf1.ch"),
            Channel(id: "3", name: "CNN", source: .xtream(streamID: 3), epgChannelID: "cnn"),
            Channel(id: "4", name: "Ohne", source: .xtream(streamID: 4)),
        ]))

        let result = try await repository.channels(forEPGIDs: ["srf1.ch", "cnn", "fehlt"], for: profileID)
        let empty = try await repository.channels(forEPGIDs: [], for: profileID)

        XCTAssertEqual(result.mapValues(\.id), ["srf1.ch": "1", "cnn": "3"])
        XCTAssertTrue(empty.isEmpty)
    }

    func testSearchVODIsPerKind() async throws {
        let repository = try SwiftDataVODRepository(inMemory: true)
        try await repository.importItems(for: profileID, kind: .movie, from: .from([
            VODItem(kind: .movie, sourceID: 1, name: "Dark Knight"),
            VODItem(kind: .movie, sourceID: 2, name: "Alien"),
        ]))
        try await repository.importItems(for: profileID, kind: .series, from: .from([VODItem(kind: .series, sourceID: 9, name: "Dark")]))

        let movies = try await repository.searchItems(for: profileID, kind: .movie, query: "dark", limit: 10)
        let series = try await repository.searchItems(for: profileID, kind: .series, query: "DARK", limit: 10)

        XCTAssertEqual(movies.map(\.id), ["movie-1"])
        XCTAssertEqual(series.map(\.id), ["series-9"])
    }

    func testSearchProgrammesRespectsTimeWindowAndOrder() async throws {
        let repository = try SwiftDataEPGRepository(inMemory: true)
        func programme(_ title: String, from offset: TimeInterval, minutes: Double) -> EPGProgramme {
            let start = now.addingTimeInterval(offset)
            return EPGProgramme(channelID: "a", start: start, stop: start.addingTimeInterval(minutes * 60), title: title)
        }
        try await repository.importProgrammes(for: profileID, from: .from([
            programme("Tagesschau spät", from: 7_200, minutes: 30),
            programme("Tagesschau läuft", from: -600, minutes: 30),
            programme("Tagesschau vorbei", from: -7_200, minutes: 30),
            programme("Tagesschau in 3 Tagen", from: 3 * 86_400, minutes: 30),
            programme("Wetter", from: 600, minutes: 5),
        ]))

        let result = try await repository.searchProgrammes(for: profileID, query: "tagesschau", from: now, to: now.addingTimeInterval(86_400), limit: 10)

        XCTAssertEqual(result.map(\.title), ["Tagesschau läuft", "Tagesschau spät"])
    }
}

final class LastUpdateTests: XCTestCase {
    private let profileID = UUID()

    func testCatalogAndVODReportTheirImportTime() async throws {
        let catalog = try SwiftDataCatalogRepository(inMemory: true)
        let vod = try SwiftDataVODRepository(inMemory: true)
        let none = try await catalog.lastUpdate(for: profileID)
        XCTAssertNil(none)

        let before = Date()
        try await catalog.importChannels(for: profileID, from: .from([Channel(id: "1", name: "A", source: .xtream(streamID: 1))]))
        try await vod.importItems(for: profileID, kind: .movie, from: .from([VODItem(kind: .movie, sourceID: 1, name: "F")]))

        let catalogDate = try await catalog.lastUpdate(for: profileID)
        let movieDate = try await vod.lastUpdate(for: profileID, kind: .movie)
        let seriesDate = try await vod.lastUpdate(for: profileID, kind: .series)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(catalogDate), before)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(movieDate), before)
        XCTAssertNil(seriesDate)
    }

    func testActiveProfileStoreRoundTrips() {
        let defaults = UserDefaults(suiteName: "arjo-tests-\(UUID())")!
        let store = UserDefaultsActiveProfileStore(defaults: defaults)
        XCTAssertNil(store.activeProfileID)
        store.setActiveProfileID(profileID)
        XCTAssertEqual(store.activeProfileID, profileID)
        store.setActiveProfileID(nil)
        XCTAssertNil(store.activeProfileID)
    }
}
