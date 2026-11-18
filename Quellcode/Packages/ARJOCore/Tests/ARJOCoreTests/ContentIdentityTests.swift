@testable import ARJOCore
import XCTest

final class ContentIdentityTests: XCTestCase {
    func testXtreamPathIgnoresCredentialsAndHost() {
        let a = URL(string: "http://alpha.example:8080/movie/anna/geheim1/12345.mkv")!
        let b = URL(string: "https://beta.example/movie/anna/neuesPasswort/12345.mp4")!
        XCTAssertEqual(ContentIdentity.locator(for: a), "movie/12345")
        XCTAssertEqual(ContentIdentity.mediaID(for: a), ContentIdentity.mediaID(for: b))
        XCTAssertFalse(ContentIdentity.locator(for: a).contains("geheim1"))
    }

    func testDifferentFoldersOrIDsStayApart() {
        let movie = URL(string: "http://x.example/movie/u/p/1.mkv")!
        let episode = URL(string: "http://x.example/series/u/p/1.mkv")!
        let other = URL(string: "http://x.example/movie/u/p/2.mkv")!
        XCTAssertNotEqual(ContentIdentity.mediaID(for: movie), ContentIdentity.mediaID(for: episode))
        XCTAssertNotEqual(ContentIdentity.mediaID(for: movie), ContentIdentity.mediaID(for: other))
    }

    func testChangingTokenKeepsChannelID() {
        let first = URL(string: "https://cdn.example/live/sport/index.m3u8?token=abc&expires=1&quality=hd")!
        let second = URL(string: "https://cdn.example/live/sport/index.m3u8?quality=hd&expires=2&token=xyz")!
        XCTAssertEqual(ContentIdentity.channelID(for: first), ContentIdentity.channelID(for: second))
        XCTAssertTrue(ContentIdentity.channelID(for: first).hasPrefix("m3u-"))
    }

    func testSameFileNameOnOtherHostIsDifferentChannel() {
        let a = URL(string: "https://one.example/index.m3u8")!
        let b = URL(string: "https://two.example/index.m3u8")!
        XCTAssertNotEqual(ContentIdentity.channelID(for: a), ContentIdentity.channelID(for: b))
    }

    func testUserInfoIsDropped() {
        let url = URL(string: "http://user:pass@host.example/a/b.ts")!
        let locator = ContentIdentity.locator(for: url)
        XCTAssertFalse(locator.contains("pass"))
        XCTAssertEqual(locator, "host.example/a/b.ts")
    }

    func testLegacyChannelIDMigration() {
        let url = "http://host.example/live/u/p/7.ts"
        XCTAssertEqual(ContentIdentity.migratedChannelID(url), ContentIdentity.channelID(for: URL(string: url)!))
        XCTAssertEqual(ContentIdentity.migratedChannelID("42"), "42")
        let migrated = ContentIdentity.migratedChannelID(url)
        XCTAssertEqual(ContentIdentity.migratedChannelID(migrated), migrated, "Migration muss idempotent sein")
    }

    func testChannelFromPlaylistEntryHasNoSecretsInID() {
        let entry = PlaylistEntry(name: "Sport", url: URL(string: "http://host.example/live/anna/geheim/7.ts")!)
        let channel = Channel(entry: entry)
        XCTAssertFalse(channel.id.contains("geheim"))
        XCTAssertFalse(channel.id.contains("anna"))
        XCTAssertEqual(channel.source, .url(entry.url), "Die Adresse zum Abspielen bleibt erhalten")
    }

    func testXtreamFingerprintIgnoresPassword() {
        let server = URL(string: "http://Host.example:8080")!
        let a = SourceFingerprint.make(for: .xtream(XtreamCredentials(serverURL: server, username: "Anna", password: "eins")))
        let b = SourceFingerprint.make(for: .xtream(XtreamCredentials(serverURL: URL(string: "http://host.example:8080")!, username: "anna", password: "zwei")))
        let other = SourceFingerprint.make(for: .xtream(XtreamCredentials(serverURL: server, username: "ben", password: "eins")))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, other)
        XCTAssertEqual(a.count, 64, "SHA-256 als Hex")
        XCTAssertFalse(a.contains("anna"))
    }

    func testPlaylistFingerprintDropsPasswordParameter() {
        let a = SourceFingerprint.make(for: .m3uURL(URL(string: "http://h.example/get.php?username=anna&password=eins&type=m3u_plus")!))
        let b = SourceFingerprint.make(for: .m3uURL(URL(string: "http://h.example/get.php?type=m3u_plus&password=zwei&username=anna")!))
        let other = SourceFingerprint.make(for: .m3uURL(URL(string: "http://h.example/get.php?username=ben&password=eins&type=m3u_plus")!))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, other)
    }

    func testStableHashIsDeterministic() {
        XCTAssertEqual(ContentIdentity.stableHash("a"), ContentIdentity.stableHash("a"))
        XCTAssertNotEqual(ContentIdentity.stableHash("a"), ContentIdentity.stableHash("b"))
        XCTAssertGreaterThan(ContentIdentity.stableHash("text"), 0)
    }
}
