import ARJOCore
import XCTest
@testable import ARJOUI

private final class FakeOrganization: OrganizationRepository, @unchecked Sendable {
    var stored: [String: Preference] = [:]
    var storedFolders: [ChannelFolder] = []
    var failOnSave = false

    func preferences(for profileID: UUID) async throws -> [String: Preference] { stored }

    func save(_ preference: Preference, for profileID: UUID) async throws {
        if failOnSave { throw URLError(.cannotWriteToFile) }
        stored[preference.key] = preference.isDefault ? nil : preference
    }

    func setFavoriteOrder(_ channelIDs: [String], for profileID: UUID) async throws {
        for (index, id) in channelIDs.enumerated() { stored[PreferenceKey.channel(id)]?.favoriteOrder = index }
    }

    func folders(for profileID: UUID) async throws -> [ChannelFolder] { storedFolders }

    func save(_ folder: ChannelFolder, for profileID: UUID) async throws {
        if let index = storedFolders.firstIndex(where: { $0.id == folder.id }) { storedFolders[index] = folder } else { storedFolders.append(folder) }
    }

    func deleteFolder(id: UUID, for profileID: UUID) async throws { storedFolders.removeAll { $0.id == id } }
    func deleteOrganization(for profileID: UUID) async throws { stored = [:]; storedFolders = [] }
}

@MainActor
final class OrganizationModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let catalog = FakeCatalog()
    private let repository = FakeOrganization()
    private let channels = (1...4).map {
        Channel(id: String($0), name: "Sender \($0)", source: .xtream(streamID: $0), groupName: "Gruppe")
    }

    override func setUp() {
        catalog.channelsByProfile[profile.id] = channels
    }

    private func makeModel() async -> OrganizationModel {
        let model = OrganizationModel(profile: profile, repository: repository, catalog: catalog)
        await model.load()
        return model
    }

    func testFavoritesKeepTheirOrderAndCanBeMoved() async {
        let model = await makeModel()
        await model.toggleFavorite(channels[2])
        await model.toggleFavorite(channels[0])
        await model.toggleFavorite(channels[3])
        XCTAssertEqual(model.favorites.map(\.id), ["3", "1", "4"])
        XCTAssertTrue(model.isFavorite(channels[0]))

        await model.moveFavorite(channels[3], by: -1)
        XCTAssertEqual(model.favorites.map(\.id), ["3", "4", "1"])

        await model.moveFavorite(channels[3], by: -5)
        XCTAssertEqual(model.favorites.map(\.id), ["3", "4", "1"], "außerhalb der Liste: keine Änderung")

        await model.toggleFavorite(channels[2])
        XCTAssertEqual(model.favorites.map(\.id), ["4", "1"])
        XCTAssertNil(repository.stored[PreferenceKey.channel("3")], "Standardwerte werden nicht gespeichert")
    }

    func testRestoresFavoritesAfterRestart() async {
        let first = await makeModel()
        await first.toggleFavorite(channels[1])
        let second = await makeModel()
        XCTAssertEqual(second.favorites.map(\.id), ["2"])
    }

    func testHideAndUnhideChannelsAndGroups() async {
        let model = await makeModel()
        await model.setHidden(true, channels[1])
        await model.setHidden(true, group: "Erwachsene", in: .movie)

        XCTAssertEqual(model.visible(channels).map(\.id), ["1", "3", "4"])
        XCTAssertEqual(model.visible([ChannelGroup(name: "Erwachsene", channelCount: 1), ChannelGroup(name: "Komödie", channelCount: 2)], in: .movie).map(\.name), ["Komödie"])
        XCTAssertEqual(model.visible([ChannelGroup(name: "Erwachsene", channelCount: 1)], in: .series).map(\.name), ["Erwachsene"], "pro Bereich")
        XCTAssertEqual(model.hiddenChannels.map(\.id), ["2"])
        XCTAssertEqual(model.hiddenGroupKeys, [PreferenceKey.group(.movie, "Erwachsene")])

        await model.setHidden(false, channels[1])
        await model.unhide(key: PreferenceKey.group(.movie, "Erwachsene"))
        XCTAssertEqual(model.visible(channels).count, 4)
        XCTAssertTrue(model.hiddenGroupKeys.isEmpty)
    }

    func testGroupsFollowTheCustomOrderAndUnorderedGroupsKeepTheirPlace() async {
        let model = await makeModel()
        let groups = ["A", "B", "C", "D"].map { ChannelGroup(name: $0, channelCount: 1) }
        XCTAssertEqual(model.ordered(groups, in: .live).map(\.name), ["A", "B", "C", "D"])
        XCTAssertFalse(model.hasCustomOrder(in: .live, groups: groups))

        await model.moveGroup("C", in: .live, among: groups, by: -2)
        XCTAssertEqual(model.ordered(groups, in: .live).map(\.name), ["C", "A", "B", "D"])
        XCTAssertTrue(model.hasCustomOrder(in: .live, groups: groups))
        XCTAssertEqual(model.ordered(groups, in: .movie).map(\.name), ["A", "B", "C", "D"], "pro Bereich")

        await model.moveGroup("C", in: .live, among: groups, by: -1)
        XCTAssertEqual(model.ordered(groups, in: .live).map(\.name), ["C", "A", "B", "D"], "oben angekommen: keine Änderung")

        await model.setHidden(true, group: "A", in: .live)
        XCTAssertEqual(model.visible(groups, in: .live).map(\.name), ["C", "B", "D"])

        // Neue Gruppe vom Anbieter hängt hinten an.
        let more = groups + [ChannelGroup(name: "E", channelCount: 1)]
        XCTAssertEqual(model.ordered(more, in: .live).map(\.name), ["C", "A", "B", "D", "E"])

        await model.resetGroupOrder(in: .live, among: groups)
        XCTAssertEqual(model.ordered(groups, in: .live).map(\.name), ["A", "B", "C", "D"])
        XCTAssertTrue(model.isHidden(group: "A", in: .live), "Ausblenden bleibt beim Zurücksetzen erhalten")
    }

    func testDraggingGroupsAndFavoritesSavesTheNewOrder() async {
        let model = await makeModel()
        let groups = ["A", "B", "C", "D"].map { ChannelGroup(name: $0, channelCount: 1) }
        await model.setHidden(true, group: "B", in: .live)

        // Ziehen bezieht sich auf alle Gruppen, auch ausgeblendete: D an die zweite Stelle.
        await model.moveGroups(in: .live, among: groups, fromOffsets: IndexSet(integer: 3), toOffset: 1)
        XCTAssertEqual(model.ordered(groups, in: .live).map(\.name), ["A", "D", "B", "C"])
        XCTAssertEqual(model.visible(groups, in: .live).map(\.name), ["A", "D", "C"])

        // Neu geladen bleibt die Reihenfolge.
        let reloaded = await makeModel()
        XCTAssertEqual(reloaded.ordered(groups, in: .live).map(\.name), ["A", "D", "B", "C"])

        for channel in channels.prefix(3) { await model.toggleFavorite(channel) }
        await model.moveFavorites(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(model.favorites.map(\.id), ["2", "3", "1"])
    }

    func testDraggingChannelsBeforeAnotherKeepsOrderPerListAndSurvivesReload() async {
        let model = await makeModel()
        XCTAssertEqual(model.ordered(channels).map(\.id), ["1", "2", "3", "4"])

        // Sender 4 an die Stelle von Sender 2 ziehen, dann Sender 1 an die Stelle von Sender 3.
        await model.moveChannel("4", to: "2", among: channels)
        XCTAssertEqual(model.ordered(channels).map(\.id), ["1", "4", "2", "3"])
        await model.moveChannel("1", to: "3", among: channels)
        XCTAssertEqual(model.ordered(channels).map(\.id), ["4", "2", "3", "1"])
        await model.moveChannel("9", to: "1", among: channels)
        XCTAssertEqual(model.ordered(channels).map(\.id), ["4", "2", "3", "1"], "unbekannter Sender ändert nichts")

        let reloaded = await makeModel()
        XCTAssertEqual(reloaded.ordered(channels).map(\.id), ["4", "2", "3", "1"])
        // Neue Sender vom Anbieter hängen hinten an.
        let more = channels + [Channel(id: "5", name: "Sender 5", source: .xtream(streamID: 5), groupName: "Gruppe")]
        XCTAssertEqual(reloaded.ordered(more).map(\.id), ["4", "2", "3", "1", "5"])

        await model.moveChannels(among: channels, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(model.ordered(channels).map(\.id), ["1", "4", "2", "3"])
    }

    func testDraggingFavoritesAndFolderChannels() async {
        let model = await makeModel()
        for channel in channels { await model.toggleFavorite(channel) }
        await model.moveFavorite("4", to: "1")
        XCTAssertEqual(model.favorites.map(\.id), ["4", "1", "2", "3"])
        await model.moveFavorite("1", to: "3")
        XCTAssertEqual(model.favorites.map(\.id), ["4", "2", "3", "1"])

        await model.createFolder(named: "Sport", adding: channels[0])
        var folder = model.folders[0]
        await model.add(channels[1], to: folder)
        folder = model.folders[0]
        await model.add(channels[2], to: folder)
        await model.move("3", to: "1", in: model.folders[0])
        XCTAssertEqual(model.folders[0].channelIDs, ["3", "1", "2"])
    }

    func testRenamingAndResettingNames() async {
        let model = await makeModel()
        await model.rename(channels[0], to: "  Mein Erster  ")
        await model.renameGroup("Gruppe", in: .live, to: "Schweiz")
        XCTAssertEqual(model.name(for: channels[0]), "Mein Erster")
        XCTAssertEqual(model.name(forGroup: "Gruppe", in: .live), "Schweiz")
        XCTAssertEqual(model.name(forGroup: "Gruppe", in: .movie), "Gruppe")

        await model.rename(channels[0], to: "   ")
        await model.renameGroup("Gruppe", in: .live, to: nil)
        XCTAssertEqual(model.name(for: channels[0]), "Sender 1")
        XCTAssertEqual(model.name(forGroup: "Gruppe", in: .live), "Gruppe")
    }

    func testFoldersCreateFillReorderRenameAndDelete() async {
        let model = await makeModel()
        await model.createFolder(named: "  ", adding: nil)
        XCTAssertTrue(model.folders.isEmpty, "leere Namen werden abgelehnt")

        await model.createFolder(named: "Sport", adding: channels[0])
        var folder = model.folders[0]
        await model.add(channels[2], to: folder)
        folder = model.folders[0]
        await model.add(channels[2], to: folder)
        folder = model.folders[0]
        XCTAssertEqual(model.folderChannels[folder.id]?.map(\.id), ["1", "3"], "doppelt hinzufügen ändert nichts")

        await model.move(channels[2], in: folder, by: -1)
        folder = model.folders[0]
        XCTAssertEqual(model.folderChannels[folder.id]?.map(\.id), ["3", "1"])

        await model.remove(channels[0], from: folder)
        folder = model.folders[0]
        XCTAssertEqual(model.folderChannels[folder.id]?.map(\.id), ["3"])

        await model.renameFolder(folder, to: "Sport live")
        XCTAssertEqual(model.folders[0].name, "Sport live")

        await model.deleteFolder(model.folders[0])
        XCTAssertTrue(model.folders.isEmpty)
        XCTAssertTrue(repository.storedFolders.isEmpty)
    }

    func testChannelsMissingFromTheCatalogAreSkipped() async {
        repository.stored[PreferenceKey.channel("99")] = Preference(key: PreferenceKey.channel("99"), isFavorite: true)
        let model = await makeModel()
        XCTAssertTrue(model.favorites.isEmpty)
    }

    func testFailedSaveKeepsLocalStateAndReportsError() async {
        let model = await makeModel()
        repository.failOnSave = true

        await model.toggleFavorite(channels[0])

        XCTAssertFalse(model.isFavorite(channels[0]))
        XCTAssertEqual(model.errorMessage, "Die Änderung konnte nicht gespeichert werden.")
    }
}
