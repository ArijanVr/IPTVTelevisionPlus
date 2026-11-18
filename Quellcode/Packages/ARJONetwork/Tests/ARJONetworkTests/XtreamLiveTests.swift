import ARJOCore
import XCTest
@testable import ARJONetwork

private final class RoutingHTTPClient: HTTPClient, @unchecked Sendable {
    var requests: [URLRequest] = []
    let routes: [String: String]

    init(_ routes: [String: String]) { self.routes = routes }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "action" }?.value ?? ""
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data((routes[action] ?? "[]").utf8), response)
    }
}

final class XtreamLiveTests: XCTestCase {
    private let credentials = XtreamCredentials(
        serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "p&ss/1")

    func testMapsStreamsToChannelsWithGroupNames() async throws {
        let http = RoutingHTTPClient([
            "get_live_categories": #"[{"category_id":"5","category_name":"Schweiz","parent_id":0},{"category_id":"6","category_name":"News"}]"#,
            "get_live_streams": """
            [{"num":1,"name":"SRF 1","stream_id":101,"stream_icon":"http://logo.example/srf1.png","epg_channel_id":"srf1.ch","category_id":"5"},
             {"num":2,"name":"CNN","stream_id":"102","stream_icon":"","epg_channel_id":null,"category_id":6},
             {"num":3,"name":null,"stream_id":103,"category_id":"99","tv_archive":1,"tv_archive_duration":"5"},
             {"num":5,"name":"Ohne Dauer","stream_id":104,"tv_archive":"1","tv_archive_duration":"0"},
             {"num":6,"name":"Aus","stream_id":105,"tv_archive":0,"tv_archive_duration":7},
             {"name":"Kaputt","stream_id":"abc"}]
            """,
        ])
        let channels = try await XtreamClient(credentials: credentials, http: http).liveChannels()

        XCTAssertEqual(channels.map(\.id), ["101", "102", "103", "104", "105"])
        XCTAssertEqual(channels.map(\.archiveDays), [nil, nil, 5, 1, nil])
        XCTAssertEqual(channels[0].name, "SRF 1")
        XCTAssertEqual(channels[0].groupName, "Schweiz")
        XCTAssertEqual(channels[0].source, .xtream(streamID: 101))
        XCTAssertEqual(channels[0].logoURL?.absoluteString, "http://logo.example/srf1.png")
        XCTAssertEqual(channels[0].epgChannelID, "srf1.ch")
        XCTAssertEqual(channels[1].groupName, "News")
        XCTAssertNil(channels[1].logoURL)
        XCTAssertNil(channels[1].epgChannelID)
        XCTAssertEqual(channels[2].name, "Sender 103")
        XCTAssertEqual(channels[2].groupName, Channel.ungroupedName)
    }

    func testNonArrayResponseIsUnexpected() async {
        let http = RoutingHTTPClient(["get_live_streams": #"{"user_info":{"auth":0}}"#])
        do {
            _ = try await XtreamClient(credentials: credentials, http: http).liveChannels()
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? XtreamError, .unexpectedResponse)
        }
    }

    func testBuildsXtreamStreamURLWithEncodedCredentials() throws {
        let channel = Channel(id: "101", name: "SRF 1", source: .xtream(streamID: 101))
        let url = try StreamURLResolver.liveURL(for: channel, credentials: .xtream(credentials))
        XCTAssertEqual(url.absoluteString, "http://example.com:8080/live/anna/p%26ss%2F1/101.m3u8")
    }

    func testBuildsTransportStreamURLForFallbackEngine() throws {
        let channel = Channel(id: "101", name: "SRF 1", source: .xtream(streamID: 101))
        let url = try StreamURLResolver.liveURL(for: channel, credentials: .xtream(credentials), transportStream: true)
        XCTAssertEqual(url.absoluteString, "http://example.com:8080/live/anna/p%26ss%2F1/101.ts")
    }

    func testUsesChannelURLForM3USources() throws {
        let direct = URL(string: "http://cdn.example/stream.m3u8?token=1")!
        let channel = Channel(id: "x", name: "X", source: .url(direct))
        XCTAssertEqual(try StreamURLResolver.liveURL(for: channel, credentials: .m3uURL(direct)), direct)
    }

    func testXtreamChannelWithM3UCredentialsFails() {
        let channel = Channel(id: "1", name: "X", source: .xtream(streamID: 1))
        XCTAssertThrowsError(try StreamURLResolver.liveURL(for: channel, credentials: .m3uURL(credentials.serverURL))) {
            XCTAssertEqual($0 as? StreamURLError, .credentialsDoNotMatchChannel)
        }
    }

    func testChannelFromPlaylistEntry() {
        let url = URL(string: "http://server.example/1.ts")!
        let entry = PlaylistEntry(name: "Arte", url: url, tvgID: "arte.de", groupTitle: nil)
        let channel = Channel(entry: entry)
        XCTAssertEqual(channel.source, .url(url))
        XCTAssertEqual(channel.groupName, Channel.ungroupedName)
        XCTAssertEqual(channel.epgChannelID, "arte.de")
    }
}
