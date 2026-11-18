import ARJOCore
import XCTest
@testable import ARJOData

final class EPGRepositoryTests: XCTestCase {
    private let profileID = UUID()
    private let now = Date(timeIntervalSince1970: 1_792_859_400)

    private func programme(_ channel: String, _ title: String, from offset: TimeInterval, minutes: Double) -> EPGProgramme {
        let start = now.addingTimeInterval(offset)
        return EPGProgramme(channelID: channel, start: start, stop: start.addingTimeInterval(minutes * 60), title: title,
                            subtitle: "Sub", description: "Beschreibung", category: "News",
                            iconURL: URL(string: "http://img.example/a.jpg"))
    }

    private func makeRepository(_ programmes: [EPGProgramme]) async throws -> SwiftDataEPGRepository {
        let repository = try SwiftDataEPGRepository(inMemory: true)
        try await repository.importProgrammes(for: profileID, from: stream(programmes))
        return repository
    }

    private func stream(_ programmes: [EPGProgramme]) -> AsyncThrowingStream<EPGProgramme, Error> {
        AsyncThrowingStream { continuation in
            programmes.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func testNowAndNextPerChannel() async throws {
        let repository = try await makeRepository([
            programme("a", "Vorher", from: -3_600, minutes: 30),
            programme("a", "Jetzt A", from: -600, minutes: 60),
            programme("a", "Danach A", from: 3_000, minutes: 60),
            programme("b", "Gleich B", from: 900, minutes: 30),
            programme("c", "Nur Ende", from: -3_000, minutes: 40),
        ])

        let result = try await repository.nowNext(for: profileID, channelIDs: ["a", "b", "c", "z"], at: now)

        XCTAssertEqual(result["a"]?.now?.title, "Jetzt A")
        XCTAssertEqual(result["a"]?.next?.title, "Danach A")
        XCTAssertNil(result["b"]?.now)
        XCTAssertEqual(result["b"]?.next?.title, "Gleich B")
        XCTAssertNil(result["c"])
        XCTAssertNil(result["z"])
    }

    func testProgrammesInWindowAreSortedAndKeepAllFields() async throws {
        let repository = try await makeRepository([
            programme("a", "Zwei", from: 3_600, minutes: 60),
            programme("a", "Eins", from: 0, minutes: 60),
            programme("a", "Ausserhalb", from: 36_000, minutes: 60),
            programme("b", "Anderer Sender", from: 0, minutes: 60),
        ])

        let result = try await repository.programmes(for: profileID, channelIDs: ["a"], from: now, to: now.addingTimeInterval(7_200))

        XCTAssertEqual(result.map(\.title), ["Eins", "Zwei"])
        XCTAssertEqual(result.first, programme("a", "Eins", from: 0, minutes: 60))
    }

    func testReimportReplacesOnlyThatProfile() async throws {
        let repository = try await makeRepository([programme("a", "Alt", from: 0, minutes: 60)])
        let other = UUID()
        try await repository.importProgrammes(for: other, from: stream([programme("a", "Fremd", from: 0, minutes: 60)]))

        try await repository.importProgrammes(for: profileID, from: stream([programme("a", "Neu", from: 0, minutes: 60)]))

        let mine = try await repository.programmes(for: profileID, channelIDs: ["a"], from: now, to: now.addingTimeInterval(60))
        let theirs = try await repository.programmes(for: other, channelIDs: ["a"], from: now, to: now.addingTimeInterval(60))
        XCTAssertEqual(mine.map(\.title), ["Neu"])
        XCTAssertEqual(theirs.map(\.title), ["Fremd"])
    }

    func testFailedImportKeepsPreviousGuide() async throws {
        let repository = try await makeRepository([programme("a", "Alt", from: 0, minutes: 60)])
        let failing = AsyncThrowingStream<EPGProgramme, Error> { continuation in
            continuation.yield(programme("a", "Halb", from: 0, minutes: 60))
            continuation.finish(throwing: URLError(.networkConnectionLost))
        }

        do {
            try await repository.importProgrammes(for: profileID, from: failing)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        let result = try await repository.programmes(for: profileID, channelIDs: ["a"], from: now, to: now.addingTimeInterval(60))
        XCTAssertEqual(result.map(\.title), ["Alt"])
    }

    func testLastUpdateAndDelete() async throws {
        let repository = try SwiftDataEPGRepository(inMemory: true)
        let before = try await repository.lastUpdate(for: profileID)
        XCTAssertNil(before)

        try await repository.importProgrammes(for: profileID, from: stream([programme("a", "A", from: 0, minutes: 60)]))
        let after = try await repository.lastUpdate(for: profileID)
        XCTAssertNotNil(after)

        try await repository.deleteEPG(for: profileID)
        let deleted = try await repository.lastUpdate(for: profileID)
        let remaining = try await repository.programmes(for: profileID, channelIDs: ["a"], from: now, to: now.addingTimeInterval(60))
        XCTAssertNil(deleted)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testImportsManyProgrammesInBatches() async throws {
        let many = (0..<12_000).map { programme("c\($0 % 100)", "P\($0)", from: Double($0), minutes: 1) }
        let repository = try await makeRepository(many)

        let result = try await repository.programmes(for: profileID, channelIDs: ["c7"], from: now, to: now.addingTimeInterval(20_000))
        XCTAssertEqual(result.count, 120)
    }

    func testCatalogReportsEPGChannelIDs() async throws {
        let catalog = try SwiftDataCatalogRepository(inMemory: true)
        try await catalog.importChannels(for: profileID, from: .from([
            Channel(id: "1", name: "A", source: .xtream(streamID: 1), epgChannelID: "a.ch"),
            Channel(id: "2", name: "B", source: .xtream(streamID: 2)),
            Channel(id: "3", name: "C", source: .xtream(streamID: 3), epgChannelID: "c.ch"),
        ]))
        let ids = try await catalog.epgChannelIDs(for: profileID)
        XCTAssertEqual(ids, ["a.ch", "c.ch"])
    }
}
