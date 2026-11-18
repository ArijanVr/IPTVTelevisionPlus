import ARJOCore
import XCTest
@testable import ARJONetwork

final class CatchupTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_792_857_600) // 2026-10-24 16:00 UTC
    private let end = Date(timeIntervalSince1970: 1_792_857_600 + 45 * 60 + 10)
    private let now = Date(timeIntervalSince1970: 1_792_861_000)
    private let credentials = XtreamCredentials(
        serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "p&ss")

    private func channel(source: ChannelSource, days: Int? = 3, type: String? = nil, template: String? = nil) -> Channel {
        Channel(id: "1", name: "SRF 1", source: source, archiveDays: days, catchupType: type, catchupTemplate: template)
    }

    func testXtreamTimeshiftURLUsesServerTimeZoneAndRoundsMinutesUp() throws {
        let url = try CatchupURLBuilder.url(
            for: channel(source: .xtream(streamID: 101)), credentials: .xtream(credentials), start: start, end: end,
            serverTimeZone: TimeZone(identifier: "Europe/Zurich")
        )
        // 16:00 UTC = 18:00 in Zürich (Sommerzeit bis 25.10.), 45 min 10 s → 46 min
        XCTAssertEqual(url.absoluteString, "http://example.com:8080/timeshift/anna/p%26ss/46/2026-10-24%3A18-00/101.m3u8")
    }

    func testXtreamDefaultsToUTC() throws {
        let url = try CatchupURLBuilder.url(for: channel(source: .xtream(streamID: 7)), credentials: .xtream(credentials), start: start, end: end)
        XCTAssertTrue(url.absoluteString.contains("2026-10-24%3A16-00"))
    }

    func testChannelWithoutArchiveIsRejected() {
        XCTAssertThrowsError(try CatchupURLBuilder.url(for: channel(source: .xtream(streamID: 1), days: nil), credentials: .xtream(credentials), start: start, end: end)) {
            XCTAssertEqual($0 as? CatchupError, .notSupported)
        }
        XCTAssertThrowsError(try CatchupURLBuilder.url(for: channel(source: .xtream(streamID: 1), days: 0), credentials: .xtream(credentials), start: start, end: end))
    }

    func testPlaylistAppendTemplate() throws {
        let stream = URL(string: "http://cdn.example/live/1.m3u8?token=abc")!
        let url = try CatchupURLBuilder.url(
            for: channel(source: .url(stream), type: "append", template: "&utc=${start}&lutc=${timestamp}&dur=${duration}"),
            credentials: .m3uURL(stream), start: start, end: end, now: now)
        XCTAssertEqual(url.absoluteString, "http://cdn.example/live/1.m3u8?token=abc&utc=1792857600&lutc=1792861000&dur=2710")
    }

    func testPlaylistAppendWithoutTemplateAndShiftUseUtcParameters() throws {
        let stream = URL(string: "http://cdn.example/live/1.m3u8")!
        let append = try CatchupURLBuilder.url(for: channel(source: .url(stream), type: "append"), credentials: .m3uURL(stream), start: start, end: end, now: now)
        XCTAssertEqual(append.absoluteString, "http://cdn.example/live/1.m3u8?utc=1792857600&lutc=1792861000")
        let withQuery = URL(string: "http://cdn.example/live/1.m3u8?a=1")!
        let shift = try CatchupURLBuilder.url(for: channel(source: .url(withQuery), type: "shift"), credentials: .m3uURL(withQuery), start: start, end: end, now: now)
        XCTAssertEqual(shift.absoluteString, "http://cdn.example/live/1.m3u8?a=1&utc=1792857600&lutc=1792861000")
    }

    func testPlaylistDefaultTemplateCanBeAFullURLWithDateParts() throws {
        let stream = URL(string: "http://cdn.example/live/1.m3u8")!
        let url = try CatchupURLBuilder.url(
            for: channel(source: .url(stream), type: "default", template: "http://cdn.example/archive/{Y}/{m}/{d}/{H}{M}{S}/${duration}.m3u8"),
            credentials: .m3uURL(stream), start: start, end: end, now: now)
        XCTAssertEqual(url.absoluteString, "http://cdn.example/archive/2026/10/24/160000/2710.m3u8")
    }

    func testFlussonicDerivesTheArchiveAddressFromTheStream() throws {
        let stream = URL(string: "http://cdn.example/ch1/index.m3u8?token=x")!
        let url = try CatchupURLBuilder.url(for: channel(source: .url(stream), type: "flussonic"), credentials: .m3uURL(stream), start: start, end: end, now: now)
        XCTAssertEqual(url.absoluteString, "http://cdn.example/ch1/video-1792857600-2710.m3u8?token=x")

        let unknown = URL(string: "http://cdn.example/ch1/stream.ts")!
        XCTAssertThrowsError(try CatchupURLBuilder.url(for: channel(source: .url(unknown), type: "flussonic"), credentials: .m3uURL(unknown), start: start, end: end))
    }

    func testPlaylistAttributesAndXtreamArchiveFlagBecomeChannelFields() async throws {
        let entry = PlaylistEntry(name: "A", url: URL(string: "http://x.example/a")!, catchupType: "append", catchupDays: 7, catchupSource: "?utc=${start}")
        let fromPlaylist = Channel(entry: entry)
        XCTAssertEqual(fromPlaylist.archiveDays, 7)
        XCTAssertEqual(fromPlaylist.catchupTemplate, "?utc=${start}")
        XCTAssertEqual(Channel(entry: PlaylistEntry(name: "B", url: URL(string: "http://x.example/b")!, catchupType: "shift")).archiveDays, 1)
        XCTAssertNil(Channel(entry: PlaylistEntry(name: "C", url: URL(string: "http://x.example/c")!)).archiveDays)
    }
}
