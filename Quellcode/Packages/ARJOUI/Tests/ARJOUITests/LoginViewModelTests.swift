import ARJOCore
import ARJONetwork
import XCTest
@testable import ARJOUI

private struct StubAuthenticator: XtreamAuthenticating {
    let result: Result<XtreamAccountInfo, XtreamError>
    func authenticate() async throws -> XtreamAccountInfo { try result.get() }
}

@MainActor
final class LoginViewModelTests: XCTestCase {
    private let store = InMemoryCredentialStore()
    private let profiles = FakeProfiles()
    private var signedIn: [Profile] = []

    private var validatedPlaylists: [URL] = []
    private var playlistError: Error?

    private func makeModel(_ result: Result<XtreamAccountInfo, XtreamError>) -> LoginViewModel {
        let model = LoginViewModel(
            makeClient: { _ in StubAuthenticator(result: result) },
            credentialStore: store,
            profileRepository: profiles,
            validatePlaylist: { [unowned self] url in
                validatedPlaylists.append(url)
                if let playlistError { throw playlistError }
            },
            importPlaylistFile: { URL(fileURLWithPath: "/App/Playlists/" + $0.lastPathComponent) },
            onSignedIn: { [unowned self] in signedIn.append($0) }
        )
        model.server = "example.com:8080"
        model.username = "anna"
        model.password = "geheim"
        return model
    }

    func testSuccessSavesCredentialsAndProfileAndNotifies() async throws {
        let model = makeModel(.success(XtreamAccountInfo(username: "anna", status: "Active")))

        await model.signIn()

        guard case .succeeded(let profile) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(profile.kind, .xtream)
        XCTAssertEqual(profile.name, "example.com")
        XCTAssertEqual(store.saved[profile.id], .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim")))
        XCTAssertEqual(profiles.stored, [profile])
        XCTAssertEqual(signedIn, [profile])
        XCTAssertEqual(model.password, "")
    }

    func testFailureShowsMessageAndSavesNothing() async {
        let model = makeModel(.failure(.invalidCredentials))

        await model.signIn()

        XCTAssertEqual(model.state, .failed("Benutzername oder Passwort sind falsch."))
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertTrue(profiles.stored.isEmpty)
        XCTAssertTrue(signedIn.isEmpty)
        XCTAssertEqual(model.password, "geheim")
    }

    func testInvalidServerInputFailsBeforeAnyRequest() async {
        let model = makeModel(.success(XtreamAccountInfo(username: "anna", status: "Active")))
        model.server = "ftp://example.com"

        await model.signIn()

        XCTAssertEqual(model.state, .failed("Die Server-Adresse ist ungültig."))
    }

    func testKeychainFailureIsReportedAndNotSignedIn() async {
        store.failOnSave = true
        let model = makeModel(.success(XtreamAccountInfo(username: "anna", status: "Active")))

        await model.signIn()

        XCTAssertEqual(model.state, .failed("Die Zugangsdaten konnten nicht sicher gespeichert werden."))
        XCTAssertTrue(signedIn.isEmpty)
    }

    func testProfileSaveFailureRemovesStoredCredentials() async {
        profiles.failOnSave = true
        let model = makeModel(.success(XtreamAccountInfo(username: "anna", status: "Active")))

        await model.signIn()

        XCTAssertEqual(model.state, .failed("Das Profil konnte nicht gespeichert werden."))
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertTrue(signedIn.isEmpty)
    }

    func testCannotSubmitWithMissingFieldsAndResetClearsForm() {
        let model = makeModel(.failure(.unexpectedResponse))
        XCTAssertTrue(model.canSubmit)
        model.password = ""
        XCTAssertFalse(model.canSubmit)

        model.reset()
        XCTAssertEqual(model.server, "")
        XCTAssertEqual(model.state, .idle)
    }

    func testPlaylistURLIsValidatedAndSavedAsM3USource() async {
        let model = makeModel(.failure(.unexpectedResponse))
        model.mode = .playlist
        model.playlistURL = " provider.example/list.m3u?token=abc "
        model.sourceName = "Meine Liste"

        await model.signIn()

        guard case .succeeded(let profile) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(profile.kind, .m3u)
        XCTAssertEqual(profile.name, "Meine Liste")
        XCTAssertEqual(validatedPlaylists.map(\.absoluteString), ["http://provider.example/list.m3u?token=abc"])
        XCTAssertEqual(store.saved[profile.id], .m3uURL(URL(string: "http://provider.example/list.m3u?token=abc")!))
        XCTAssertEqual(signedIn, [profile])
    }

    func testPlaylistNameDefaultsToHostAndBadAddressesAreRejected() async {
        let model = makeModel(.failure(.unexpectedResponse))
        model.mode = .playlist
        model.playlistURL = "ftp://x.example/a.m3u"
        await model.signIn()
        XCTAssertEqual(model.state, .failed("Die Playlist-Adresse ist ungültig."))
        XCTAssertTrue(validatedPlaylists.isEmpty)

        model.playlistURL = "https://cdn.example/a.m3u"
        await model.signIn()
        XCTAssertEqual(signedIn.first?.name, "cdn.example")
    }

    func testPlaylistValidationFailureSavesNothing() async {
        playlistError = M3UParseError.missingHeader
        let model = makeModel(.failure(.unexpectedResponse))
        model.mode = .playlist
        model.playlistURL = "http://x.example/a.html"

        await model.signIn()

        XCTAssertEqual(model.state, .failed("Die Datei ist keine gültige M3U-Playlist."))
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertTrue(profiles.stored.isEmpty)
    }

    func testChosenFileIsCopiedValidatedAndNamedAfterTheFile() async {
        let model = makeModel(.failure(.unexpectedResponse))
        model.mode = .playlist

        await model.signIn(withPlaylistFile: URL(fileURLWithPath: "/Downloads/Schweizer TV.m3u"))

        guard case .succeeded(let profile) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(profile.name, "Schweizer TV")
        XCTAssertEqual(store.saved[profile.id], .m3uURL(URL(fileURLWithPath: "/App/Playlists/Schweizer TV.m3u")))
        XCTAssertTrue(model.supportsFileImport)
    }
}
