import ARJOCore
import XCTest
@testable import ARJOData

final class VODRepositoryTests: XCTestCase {
    private let profileID = UUID()

    private func item(_ id: Int, kind: VODKind = .movie, group: String) -> VODItem {
        VODItem(kind: kind, sourceID: id, name: "Titel \(id)", posterURL: URL(string: "http://img.example/\(id).jpg"),
                groupName: group, rating: 7.5, year: "1999", containerExtension: kind == .movie ? "mkv" : nil,
                addedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testImportKeepsKindsSeparateAndRoundTripsFields() async throws {
        let repository = try SwiftDataVODRepository(inMemory: true)
        try await repository.importItems(for: profileID, kind: .movie, from: .from([item(1, group: "Action"), item(2, group: "Drama"), item(3, group: "Action")]))
        try await repository.importItems(for: profileID, kind: .series, from: .from([item(1, kind: .series, group: "Krimi")]))

        let movieGroups = try await repository.groups(for: profileID, kind: .movie)
        let seriesGroups = try await repository.groups(for: profileID, kind: .series)
        let action = try await repository.items(for: profileID, kind: .movie, group: "Action", limit: 10)

        XCTAssertEqual(movieGroups, [ChannelGroup(name: "Action", channelCount: 2), ChannelGroup(name: "Drama", channelCount: 1)])
        XCTAssertEqual(seriesGroups, [ChannelGroup(name: "Krimi", channelCount: 1)])
        XCTAssertEqual(action, [item(1, group: "Action"), item(3, group: "Action")])
    }

    func testReimportReplacesOnlyThatKind() async throws {
        let repository = try SwiftDataVODRepository(inMemory: true)
        try await repository.importItems(for: profileID, kind: .movie, from: .from([item(1, group: "Alt")]))
        try await repository.importItems(for: profileID, kind: .series, from: .from([item(9, kind: .series, group: "Serien")]))

        try await repository.importItems(for: profileID, kind: .movie, from: .from([item(2, group: "Neu")]))

        let movieGroups = try await repository.groups(for: profileID, kind: .movie)
        let seriesGroups = try await repository.groups(for: profileID, kind: .series)
        let oldItems = try await repository.items(for: profileID, kind: .movie, group: "Alt", limit: 10)
        XCTAssertEqual(movieGroups.map(\.name), ["Neu"])
        XCTAssertEqual(seriesGroups.map(\.name), ["Serien"])
        XCTAssertTrue(oldItems.isEmpty)
    }

    func testFailedImportKeepsPreviousList() async throws {
        let repository = try SwiftDataVODRepository(inMemory: true)
        try await repository.importItems(for: profileID, kind: .movie, from: .from([item(1, group: "Alt")]))
        let failing = AsyncThrowingStream<VODItem, Error> { continuation in
            continuation.yield(item(2, group: "Neu"))
            continuation.finish(throwing: URLError(.networkConnectionLost))
        }

        do {
            try await repository.importItems(for: profileID, kind: .movie, from: failing)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        let groups = try await repository.groups(for: profileID, kind: .movie)
        let partial = try await repository.items(for: profileID, kind: .movie, group: "Neu", limit: 10)
        XCTAssertEqual(groups.map(\.name), ["Alt"])
        XCTAssertTrue(partial.isEmpty)
    }

    func testRecentItemsAreNewestFirstAndSkipUndatedOnes() async throws {
        let repository = try SwiftDataVODRepository(inMemory: true)
        func dated(_ id: Int, _ day: Double?) -> VODItem {
            VODItem(kind: .movie, sourceID: id, name: "Film \(id)", groupName: "G", addedAt: day.map { Date(timeIntervalSince1970: 1_700_000_000 + $0 * 86_400) })
        }
        try await repository.importItems(for: profileID, kind: .movie, from: .from([dated(1, 3), dated(2, nil), dated(3, 10), dated(4, 7)]))

        let recent = try await repository.recentItems(for: profileID, kind: .movie, limit: 2)
        let none = try await repository.recentItems(for: profileID, kind: .series, limit: 5)

        XCTAssertEqual(recent.map(\.sourceID), [3, 4])
        XCTAssertTrue(none.isEmpty)
    }

    func testLimitAndDelete() async throws {
        let repository = try SwiftDataVODRepository(inMemory: true)
        try await repository.importItems(for: profileID, kind: .movie, from: .from((0..<5).map { item($0, group: "G") }))
        let limited = try await repository.items(for: profileID, kind: .movie, group: "G", limit: 2)
        XCTAssertEqual(limited.map(\.sourceID), [0, 1])

        try await repository.deleteVOD(for: profileID)
        let groups = try await repository.groups(for: profileID, kind: .movie)
        XCTAssertTrue(groups.isEmpty)
    }
}

final class ProgressRepositoryTests: XCTestCase {
    private let profileID = UUID()
    private func repository() throws -> SwiftDataProgressRepository {
        try SwiftDataProfileRepository(inMemory: true).makeProgressRepository()
    }

    private let movie = PlaybackTarget(kind: .movie, streamID: 1, containerExtension: "mkv", title: "Heat",
                                       posterURL: URL(string: "http://img.example/h.jpg"), groupName: "Action")

    private func episode(_ id: Int, series: Int) -> PlaybackTarget {
        PlaybackTarget(kind: .episode, streamID: id, title: "E\(id)", subtitle: "Serie \(series)", seriesID: series)
    }

    func testSaveAndReadBackUpdatesExistingEntry() async throws {
        let repository = try repository()
        try await repository.save(WatchProgress(target: movie, position: 100, duration: 6_000, watched: false), for: profileID)
        try await repository.save(WatchProgress(target: movie, position: 250, duration: 6_000, watched: false), for: profileID)

        let result = try await repository.progress(for: profileID, ids: [movie.id, "unbekannt"])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[movie.id]?.position, 250)
        XCTAssertEqual(result[movie.id]?.target, movie)
    }

    func testContinueWatchingSkipsWatchedAndBarelyStartedAndKeepsLatestEpisodePerSeries() async throws {
        let repository = try repository()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func save(_ target: PlaybackTarget, position: Double, watched: Bool = false, age: Double) async throws {
            try await repository.save(
                WatchProgress(target: target, position: position, duration: 3_000, watched: watched, updatedAt: base.addingTimeInterval(age)),
                for: profileID)
        }
        try await save(movie, position: 600, age: 10)
        try await save(episode(11, series: 5), position: 300, age: 20)
        try await save(episode(12, series: 5), position: 200, age: 30)
        try await save(PlaybackTarget(kind: .movie, streamID: 2, title: "Fertig"), position: 2_900, watched: true, age: 40)
        try await save(PlaybackTarget(kind: .movie, streamID: 3, title: "Kaum"), position: 4, age: 50)

        let result = try await repository.continueWatching(for: profileID, limit: 10)

        XCTAssertEqual(result.map(\.id), ["episode-12", "movie-1"])
        let limited = try await repository.continueWatching(for: profileID, limit: 1)
        XCTAssertEqual(limited.map(\.id), ["episode-12"])
    }

    func testSetWatchedCreatesOrResetsEntries() async throws {
        let repository = try repository()
        try await repository.setWatched(true, target: movie, for: profileID)
        let created = try await repository.progress(for: profileID, ids: [movie.id])
        XCTAssertEqual(created[movie.id]?.watched, true)

        try await repository.save(WatchProgress(target: movie, position: 500, duration: 6_000, watched: false), for: profileID)
        try await repository.setWatched(false, target: movie, for: profileID)
        let reset = try await repository.progress(for: profileID, ids: [movie.id])
        XCTAssertEqual(reset[movie.id]?.watched, false)
        XCTAssertEqual(reset[movie.id]?.position, 0)
    }

    func testProgressIsPerProfileAndDeletable() async throws {
        let repository = try repository()
        let other = UUID()
        try await repository.save(WatchProgress(target: movie, position: 100, duration: 6_000, watched: false), for: profileID)
        try await repository.save(WatchProgress(target: movie, position: 999, duration: 6_000, watched: false), for: other)

        try await repository.deleteProgress(for: profileID)

        let mine = try await repository.progress(for: profileID, ids: [movie.id])
        let theirs = try await repository.progress(for: other, ids: [movie.id])
        XCTAssertTrue(mine.isEmpty)
        XCTAssertEqual(theirs[movie.id]?.position, 999)
    }
}
