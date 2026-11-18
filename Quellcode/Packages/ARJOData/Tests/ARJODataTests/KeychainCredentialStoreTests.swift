import ARJOCore
import XCTest
@testable import ARJOData

final class KeychainCredentialStoreTests: XCTestCase {
    private var store: KeychainCredentialStore!
    private let profileID = UUID()

    override func setUp() {
        // Eigener Service, damit Tests echte Einträge nie berühren.
        store = KeychainCredentialStore(service: "ch.arjo.iptelevision.tests.\(UUID())", synchronizable: false)
    }

    override func tearDown() {
        try? store.delete(for: profileID)
    }

    func testSaveLoadReplaceDelete() throws {
        let server = URL(string: "http://example.com:8080")!
        let first = SourceCredentials.xtream(XtreamCredentials(serverURL: server, username: "anna", password: "a"))
        let second = SourceCredentials.m3uURL(URL(string: "http://example.com/list.m3u?token=abc")!)

        do {
            XCTAssertNil(try store.load(for: profileID))
            try store.save(first, for: profileID)
        } catch KeychainError.unexpectedStatus(let status) where status == errSecMissingEntitlement || status == errSecInteractionNotAllowed {
            throw XCTSkip("Keychain in dieser Umgebung nicht nutzbar (OSStatus \(status)). In Xcode auf einem Simulator ausführen.")
        }
        XCTAssertEqual(try store.load(for: profileID), first)

        try store.save(second, for: profileID)
        XCTAssertEqual(try store.load(for: profileID), second)

        try store.delete(for: profileID)
        XCTAssertNil(try store.load(for: profileID))
    }

    func testDeleteOfMissingEntryDoesNotThrow() {
        XCTAssertNoThrow(try store.delete(for: UUID()))
    }
}
