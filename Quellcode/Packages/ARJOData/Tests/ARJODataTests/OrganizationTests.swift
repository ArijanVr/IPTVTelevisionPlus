import ARJOCore
import XCTest
@testable import ARJOData

final class OrganizationRepositoryTests: XCTestCase {
    private let profileID = UUID()
    private func repository() throws -> SwiftDataOrganizationRepository {
        try SwiftDataProfileRepository(inMemory: true).makeOrganizationRepository()
    }

    func testSaveUpdateAndDeleteWhenBackToDefault() async throws {
        let repository = try repository()
        let key = PreferenceKey.channel("42")

        try await repository.save(Preference(key: key, isFavorite: true, favoriteOrder: 3, customName: "Mein Sender"), for: profileID)
        var stored = try await repository.preferences(for: profileID)
        XCTAssertEqual(stored[key], Preference(key: key, isFavorite: true, favoriteOrder: 3, customName: "Mein Sender"))

        try await repository.save(Preference(key: key, isHidden: true), for: profileID)
        stored = try await repository.preferences(for: profileID)
        XCTAssertEqual(stored[key]?.isHidden, true)
        XCTAssertEqual(stored[key]?.isFavorite, false)
        XCTAssertNil(stored[key]?.customName)

        try await repository.save(Preference(key: key), for: profileID)
        stored = try await repository.preferences(for: profileID)
        XCTAssertTrue(stored.isEmpty, "Einträge ohne Abweichung werden nicht gespeichert")
    }

    func testGroupSortIndexIsKeptAndKeepsTheEntryAlive() async throws {
        let repository = try repository()
        let key = PreferenceKey.group(.movie, "Action")
        try await repository.save(Preference(key: key, sortIndex: 2), for: profileID)
        var stored = try await repository.preferences(for: profileID)
        XCTAssertEqual(stored[key]?.sortIndex, 2)

        try await repository.save(Preference(key: key), for: profileID)
        stored = try await repository.preferences(for: profileID)
        XCTAssertTrue(stored.isEmpty)
    }

    func testFavoriteOrderIsRewrittenFromTheList() async throws {
        let repository = try repository()
        for (index, id) in ["a", "b", "c"].enumerated() {
            try await repository.save(Preference(key: PreferenceKey.channel(id), isFavorite: true, favoriteOrder: index), for: profileID)
        }

        try await repository.setFavoriteOrder(["c", "a", "b"], for: profileID)

        let stored = try await repository.preferences(for: profileID)
        XCTAssertEqual(["a", "b", "c"].map { stored[PreferenceKey.channel($0)]?.favoriteOrder }, [1, 2, 0])
    }

    func testPreferencesArePerProfile() async throws {
        let repository = try repository()
        let other = UUID()
        try await repository.save(Preference(key: PreferenceKey.group(.live, "Erwachsene"), isHidden: true), for: profileID)
        let mine = try await repository.preferences(for: profileID)
        let theirs = try await repository.preferences(for: other)
        XCTAssertEqual(mine.count, 1)
        XCTAssertTrue(theirs.isEmpty)
    }

    func testFoldersKeepOrderAndContent() async throws {
        let repository = try repository()
        let sport = ChannelFolder(name: "Sport", channelIDs: ["1", "2"])
        let news = ChannelFolder(name: "News")
        try await repository.save(sport, for: profileID)
        try await repository.save(news, for: profileID)

        var renamed = sport
        renamed.name = "Sport live"
        renamed.channelIDs = ["2", "1", "3"]
        try await repository.save(renamed, for: profileID)

        let folders = try await repository.folders(for: profileID)
        XCTAssertEqual(folders, [renamed, news])

        try await repository.deleteFolder(id: sport.id, for: profileID)
        let remaining = try await repository.folders(for: profileID)
        XCTAssertEqual(remaining, [news])
    }

    func testDeleteOrganizationRemovesEverythingOfThatProfile() async throws {
        let repository = try repository()
        let other = UUID()
        try await repository.save(Preference(key: "channel:1", isFavorite: true), for: profileID)
        try await repository.save(ChannelFolder(name: "A"), for: profileID)
        try await repository.save(Preference(key: "channel:1", isFavorite: true), for: other)

        try await repository.deleteOrganization(for: profileID)

        let mine = try await repository.preferences(for: profileID)
        let folders = try await repository.folders(for: profileID)
        let theirs = try await repository.preferences(for: other)
        XCTAssertTrue(mine.isEmpty)
        XCTAssertTrue(folders.isEmpty)
        XCTAssertEqual(theirs.count, 1)
    }
}
