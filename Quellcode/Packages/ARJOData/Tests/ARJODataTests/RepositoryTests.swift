import ARJOCore
import XCTest
@testable import ARJOData

final class CatalogRepositoryTests: XCTestCase {
    private let profileID = UUID()

    private func channel(_ id: Int, group: String) -> Channel {
        Channel(id: String(id), name: "Sender \(id)", source: .xtream(streamID: id), groupName: group)
    }

    func testImportCreatesOrderedGroupsAndChannels() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        let channels = [channel(1, group: "News"), channel(2, group: "Sport"), channel(3, group: "News")]
        try await repository.importChannels(for: profileID, from: .from(channels))

        let groups = try await repository.groups(for: profileID)
        let news = try await repository.channels(for: profileID, group: "News", limit: 10)
        let limited = try await repository.channels(for: profileID, group: "News", limit: 1)
        let single = try await repository.channel(id: "2", for: profileID)

        XCTAssertEqual(groups, [ChannelGroup(name: "News", channelCount: 2), ChannelGroup(name: "Sport", channelCount: 1)])
        XCTAssertEqual(news.map(\.id), ["1", "3"])
        XCTAssertEqual(limited.map(\.id), ["1"])
        XCTAssertEqual(single?.source, .xtream(streamID: 2))
    }

    func testKeepsURLSourcesAndOptionalFields() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        let url = URL(string: "http://cdn.example/a.m3u8")!
        let original = Channel(id: url.absoluteString, name: "A", source: .url(url),
                               logoURL: URL(string: "http://logo.example/a.png"), groupName: "G", epgChannelID: "a.de",
                               archiveDays: 3, catchupType: "append", catchupTemplate: "?utc=${start}")
        try await repository.importChannels(for: profileID, from: .from([original]))
        let loaded = try await repository.channel(id: original.id, for: profileID)
        var expected = original
        expected.number = 1
        XCTAssertEqual(loaded, expected)
    }

    func testReimportReplacesOldCatalogOnlyForThatProfile() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        let other = UUID()
        try await repository.importChannels(for: profileID, from: .from([channel(1, group: "Alt")]))
        try await repository.importChannels(for: other, from: .from([channel(9, group: "Fremd")]))

        try await repository.importChannels(for: profileID, from: .from([channel(2, group: "Neu")]))

        let groups = try await repository.groups(for: profileID)
        let old = try await repository.channel(id: "1", for: profileID)
        let new = try await repository.channel(id: "2", for: profileID)
        let otherGroups = try await repository.groups(for: other)
        XCTAssertEqual(groups.map(\.name), ["Neu"])
        XCTAssertNil(old)
        XCTAssertEqual(new?.name, "Sender 2")
        XCTAssertEqual(otherGroups.map(\.name), ["Fremd"])
    }

    func testFailedImportKeepsPreviousCatalogVisible() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([channel(1, group: "Alt")]))

        let failing = AsyncThrowingStream<Channel, Error> { continuation in
            continuation.yield(channel(2, group: "Neu"))
            continuation.finish(throwing: URLError(.networkConnectionLost))
        }
        do {
            try await repository.importChannels(for: profileID, from: failing)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        let groups = try await repository.groups(for: profileID)
        let old = try await repository.channels(for: profileID, group: "Alt", limit: 10)
        let partial = try await repository.channels(for: profileID, group: "Neu", limit: 10)
        XCTAssertEqual(groups.map(\.name), ["Alt"])
        XCTAssertEqual(old.map(\.id), ["1"])
        XCTAssertTrue(partial.isEmpty)
    }

    func testDeleteCatalog() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([channel(1, group: "G")]))
        try await repository.deleteCatalog(for: profileID)
        let groups = try await repository.groups(for: profileID)
        let removed = try await repository.channel(id: "1", for: profileID)
        XCTAssertTrue(groups.isEmpty)
        XCTAssertNil(removed)
    }

    func testImportsLargeCatalogInBatches() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        let channels = (0..<10_000).map { channel($0, group: "Gruppe \($0 % 20)") }
        try await repository.importChannels(for: profileID, from: .from(channels))

        let groups = try await repository.groups(for: profileID)
        let last = try await repository.channel(id: "9999", for: profileID)
        XCTAssertEqual(groups.count, 20)
        XCTAssertEqual(groups.map(\.channelCount).reduce(0, +), 10_000)
        XCTAssertEqual(last?.groupName, "Gruppe 19")
    }
}

final class ProfileRepositoryTests: XCTestCase {
    func testSaveListUpdateDelete() async throws {
        let repository = try SwiftDataProfileRepository(inMemory: true)
        var profile = Profile(name: "Anbieter", kind: .xtream)

        try await repository.save(profile)
        let saved = try await repository.profiles()
        XCTAssertEqual(saved, [profile])

        profile.name = "Umbenannt"
        try await repository.save(profile)
        let renamed = try await repository.profiles()
        XCTAssertEqual(renamed.map(\.name), ["Umbenannt"])

        try await repository.delete(id: profile.id)
        let remaining = try await repository.profiles()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testLastChannelIsStoredPerProfile() async throws {
        let repository = try SwiftDataProfileRepository(inMemory: true)
        let first = Profile(name: "A", kind: .xtream)
        let second = Profile(name: "B", kind: .m3u)
        try await repository.save(first)
        try await repository.save(second)

        try await repository.setLiveResumeState(LiveResumeState(channelID: "42"), for: first.id)

        let firstLast = try await repository.liveResumeState(for: first.id)
        let secondLast = try await repository.liveResumeState(for: second.id)
        XCTAssertEqual(firstLast?.channelID, "42")
        XCTAssertNil(firstLast?.timeshiftInstant)
        XCTAssertNil(secondLast)
    }
}

final class ChannelNumberStabilityTests: XCTestCase {
    private let profileID = UUID()

    private func channel(_ id: Int, group: String = "G", source: Int? = nil) -> Channel {
        Channel(id: String(id), name: "Testsender \(id)", source: .xtream(streamID: id), groupName: group, sourceNumber: source)
    }

    func testNumbersAreStableAcrossReimport() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([channel(1), channel(2, group: "H"), channel(3)]))
        try await repository.importChannels(for: profileID, from: .from([channel(9), channel(3), channel(1), channel(2, group: "H")]))
        let numbers = try await ["1", "2", "3", "9"].asyncMap { try await repository.channel(id: $0, for: profileID)?.number }
        XCTAssertEqual(numbers, [1, 2, 3, 4])
    }

    func testLookupByNumberAndFirstChannel() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([channel(10, source: 5), channel(11, source: 2)]))
        let byNumber = try await repository.channel(number: 5, for: profileID)
        let missing = try await repository.channel(number: 99, for: profileID)
        let first = try await repository.firstChannel(for: profileID)
        XCTAssertEqual(byNumber?.id, "10")
        XCTAssertNil(missing)
        XCTAssertEqual(first?.id, "11")
    }

    func testGroupListIsSortedByNumberAndSameNumberInEveryFetch() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([channel(1, source: 30), channel(2, source: 10)]))
        let group = try await repository.channels(for: profileID, group: "G", limit: 10)
        let found = try await repository.searchChannels(for: profileID, query: "Testsender 1", limit: 5)
        XCTAssertEqual(group.map(\.number), [10, 30])
        XCTAssertEqual(found.first?.number, 30)
    }
}

final class ChannelNumberEditingTests: XCTestCase {
    private let profileID = UUID()

    private func channel(_ id: Int, group: String) -> Channel {
        Channel(id: String(id), name: "Testsender \(id)", source: .xtream(streamID: id), groupName: group)
    }

    func testSetNumberSwapsOnConflictAndSurvivesReimport() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        let list = [channel(1, group: "A"), channel(2, group: "A"), channel(3, group: "B")]
        try await repository.importChannels(for: profileID, from: .from(list))
        try await repository.setNumber(2, forChannelID: "1", for: profileID)
        try await repository.importChannels(for: profileID, from: .from(list))
        let one = try await repository.channel(id: "1", for: profileID)
        let two = try await repository.channel(id: "2", for: profileID)
        XCTAssertEqual(one?.number, 2)
        XCTAssertEqual(two?.number, 1)
    }

    func testSetNumberToFreeNumberLeavesGap() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([channel(1, group: "A"), channel(2, group: "A")]))
        try await repository.setNumber(50, forChannelID: "2", for: profileID)
        let byNumber = try await repository.channel(number: 50, for: profileID)
        XCTAssertEqual(byNumber?.id, "2")
    }

    func testRenumberByGroupsFollowsGroupOrder() async throws {
        let repository = try SwiftDataCatalogRepository(inMemory: true)
        try await repository.importChannels(for: profileID, from: .from([channel(1, group: "A"), channel(2, group: "B"), channel(3, group: "A")]))
        try await repository.renumberByGroups(["B", "A"], for: profileID)
        var numbers: [String: Int?] = [:]
        for id in ["1", "2", "3"] { numbers[id] = try await repository.channel(id: id, for: profileID)?.number }
        XCTAssertEqual(numbers["2"], 1)
        XCTAssertEqual(numbers["1"], 2)
        XCTAssertEqual(numbers["3"], 3)
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out.append(try await transform(e)) }
        return out
    }
}
