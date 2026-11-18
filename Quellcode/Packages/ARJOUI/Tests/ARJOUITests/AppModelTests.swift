import ARJOCore
import XCTest
@testable import ARJOUI

@MainActor
final class AppModelTests: XCTestCase {
    private let profiles = FakeProfiles()
    private let catalog = FakeCatalog()
    private let epg = FakeEPG()
    private let store = InMemoryCredentialStore()
    private let active = FakeActiveProfile()

    private func makeModel() -> AppModel {
        AppModel(
            profiles: profiles, activeProfile: active, credentialStore: store,
            cleanups: [
                { [catalog] in try await catalog.deleteCatalog(for: $0) },
                { [epg] in try await epg.deleteEPG(for: $0) },
            ]
        )
    }

    func testBootstrapWithoutProfileNeedsLogin() async {
        let model = makeModel()
        await model.bootstrap()
        XCTAssertEqual(model.phase, .needsLogin)
    }

    func testBootstrapWithProfileGoesLive() async {
        let profile = Profile(name: "A", kind: .xtream)
        profiles.stored = [profile]
        let model = makeModel()
        await model.bootstrap()
        XCTAssertEqual(model.phase, .live(profile))
    }

    func testSignOutRemovesProfileCredentialsAndCatalog() async {
        let profile = Profile(name: "A", kind: .xtream)
        profiles.stored = [profile]
        store.saved[profile.id] = .m3uURL(URL(string: "http://x.example/a.m3u")!)
        catalog.channelsByProfile[profile.id] = [Channel(id: "1", name: "A", source: .xtream(streamID: 1))]
        let model = makeModel()
        model.signedIn(profile)

        await model.signOut(profile)

        XCTAssertEqual(model.phase, .needsLogin)
        XCTAssertTrue(profiles.stored.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertNil(catalog.channelsByProfile[profile.id])
        XCTAssertEqual(epg.deleted, [profile.id])
    }

    func testSignOutFailureKeepsSessionAndReportsError() async {
        let profile = Profile(name: "A", kind: .xtream)
        profiles.stored = [profile]
        catalog.failOnDelete = true
        let model = makeModel()
        model.signedIn(profile)

        await model.signOut(profile)

        XCTAssertEqual(model.phase, .live(profile))
        XCTAssertEqual(model.errorMessage, "Abmelden ist fehlgeschlagen.")
        XCTAssertEqual(profiles.stored, [profile])
    }

    func testBootstrapRestoresTheLastActiveProfile() async {
        let first = Profile(name: "A", kind: .xtream), second = Profile(name: "B", kind: .xtream)
        profiles.stored = [first, second]
        active.id = second.id
        let model = makeModel()

        await model.bootstrap()

        XCTAssertEqual(model.phase, .live(second))
        XCTAssertEqual(model.profiles, [first, second])
    }

    func testSwitchingAndAddingProfiles() async {
        let first = Profile(name: "A", kind: .xtream), second = Profile(name: "B", kind: .xtream)
        profiles.stored = [first]
        let model = makeModel()
        await model.bootstrap()
        XCTAssertTrue(model.canCancelLogin)

        model.beginAddingProfile()
        XCTAssertEqual(model.phase, .needsLogin)
        model.cancelLogin()
        XCTAssertEqual(model.phase, .live(first))

        model.beginAddingProfile()
        model.signedIn(second)
        XCTAssertEqual(model.phase, .live(second))
        XCTAssertEqual(active.id, second.id)
        XCTAssertEqual(model.profiles, [first, second])

        model.switchTo(first)
        XCTAssertEqual(model.phase, .live(first))
        XCTAssertEqual(active.id, first.id)
    }

    func testRemovingTheActiveProfileSwitchesToAnotherOrLogin() async {
        let first = Profile(name: "A", kind: .xtream), second = Profile(name: "B", kind: .xtream)
        profiles.stored = [first, second]
        store.saved[first.id] = .m3uURL(URL(string: "http://x.example/a.m3u")!)
        let model = makeModel()
        await model.bootstrap()

        await model.signOut(first)
        XCTAssertEqual(model.phase, .live(second))
        XCTAssertNil(store.saved[first.id])

        await model.signOut(second)
        XCTAssertEqual(model.phase, .needsLogin)
        XCTAssertNil(active.id)
        XCTAssertFalse(model.canCancelLogin)
    }

    func testRemovingAnotherProfileKeepsTheCurrentOne() async {
        let first = Profile(name: "A", kind: .xtream), second = Profile(name: "B", kind: .xtream)
        profiles.stored = [first, second]
        let model = makeModel()
        await model.bootstrap()

        await model.signOut(second)

        XCTAssertEqual(model.phase, .live(first))
        XCTAssertEqual(model.profiles, [first])
    }
}
