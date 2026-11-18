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

final class XtreamVODTests: XCTestCase {
    private let credentials = XtreamCredentials(
        serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "p&ss/1")

    private func client(_ routes: [String: String]) -> (XtreamClient, RoutingHTTPClient) {
        let http = RoutingHTTPClient(routes)
        return (XtreamClient(credentials: credentials, http: http), http)
    }

    func testMapsMovies() async throws {
        let (client, _) = client([
            "get_vod_categories": #"[{"category_id":"7","category_name":"Action"}]"#,
            "get_vod_streams": """
            [{"num":1,"name":"Heat","stream_id":501,"stream_icon":"http://img.example/heat.jpg","rating":"8.3","added":"1700000000",
              "category_id":"7","container_extension":"mkv","year":"1995"},
             {"name":null,"stream_id":"502","stream_icon":"","rating":0,"category_id":"99","container_extension":""},
             {"name":"Kaputt","stream_id":"x"}]
            """,
        ])

        let items = try await client.vodItems(kind: .movie)

        XCTAssertEqual(items.map(\.id), ["movie-501", "movie-502"])
        XCTAssertEqual(items[0].name, "Heat")
        XCTAssertEqual(items[0].groupName, "Action")
        XCTAssertEqual(items[0].rating, 8.3)
        XCTAssertEqual(items[0].year, "1995")
        XCTAssertEqual(items[0].containerExtension, "mkv")
        XCTAssertEqual(items[0].addedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(items[1].name, "Film 502")
        XCTAssertNil(items[1].rating)
        XCTAssertNil(items[1].posterURL)
        XCTAssertNil(items[1].containerExtension)
        XCTAssertEqual(items[1].groupName, Channel.ungroupedName)
    }

    func testMapsSeriesWithYearFromReleaseDate() async throws {
        let (client, _) = client([
            "get_series_categories": #"[{"category_id":"3","category_name":"Drama"}]"#,
            "get_series": """
            [{"series_id":42,"name":"Dark","cover":"http://img.example/dark.jpg","rating":"8.7","releaseDate":"2017-12-01","category_id":"3"},
             {"series_id":43,"name":"Ohne Datum","releaseDate":"","category_id":"3"}]
            """,
        ])

        let items = try await client.vodItems(kind: .series)

        XCTAssertEqual(items.map(\.id), ["series-42", "series-43"])
        XCTAssertEqual(items[0].year, "2017")
        XCTAssertEqual(items[0].groupName, "Drama")
        XCTAssertNil(items[1].year)
    }

    func testMovieDetailToleratesEmptyInfoArray() async throws {
        let item = VODItem(kind: .movie, sourceID: 501, name: "Heat")
        let (empty, _) = client(["get_vod_info": #"{"info":[],"movie_data":{"stream_id":501}}"#])
        let detail = try await empty.movieDetail(for: item)
        XCTAssertNil(detail.plot)
        XCTAssertNil(detail.containerExtension)
    }

    func testMovieDetailMapsFieldsAndSendsVodID() async throws {
        let item = VODItem(kind: .movie, sourceID: 501, name: "Heat")
        let (client, http) = client(["get_vod_info": """
        {"info":{"plot":"Ein Cop.","genre":"Action","cast":"Pacino","director":"Mann","rating":"8.3",
                 "releasedate":"1995-12-15","duration_secs":10200,"backdrop_path":["http://img.example/b.jpg"]},
         "movie_data":{"stream_id":501,"container_extension":"mp4"}}
        """])

        let detail = try await client.movieDetail(for: item)

        XCTAssertEqual(detail.plot, "Ein Cop.")
        XCTAssertEqual(detail.durationSeconds, 10_200)
        XCTAssertEqual(detail.rating, 8.3)
        XCTAssertEqual(detail.releaseDate, "1995-12-15")
        XCTAssertEqual(detail.backdropURL?.absoluteString, "http://img.example/b.jpg")
        XCTAssertEqual(detail.containerExtension, "mp4")
        XCTAssertTrue(http.requests[0].url!.absoluteString.hasSuffix("&action=get_vod_info&vod_id=501"))
    }

    private let seriesInfoByObject = """
    {"info":{"plot":"Zeitreisen.","genre":"Mystery","rating":"8.7","releaseDate":"2017-12-01","backdrop_path":"http://img.example/b.jpg"},
     "episodes":{
       "2":[{"id":"902","episode_num":1,"title":"S2E1","container_extension":"mkv","season":2,"info":{"duration_secs":3000}}],
       "1":[{"id":"902x","episode_num":1,"title":"kaputt","season":1},
            {"id":"102","episode_num":2,"title":"Zweite","container_extension":"mp4","season":1,"info":{"plot":"Plot","movie_image":"http://img.example/e.jpg","duration_secs":"2700"}},
            {"id":"101","episode_num":"1","title":"Erste","season":1}]}}
    """

    func testSeriesDetailGroupsAndSortsEpisodes() async throws {
        let item = VODItem(kind: .series, sourceID: 42, name: "Dark")
        let (client, http) = client(["get_series_info": seriesInfoByObject])

        let detail = try await client.seriesDetail(for: item)

        XCTAssertEqual(detail.seasons.map(\.number), [1, 2])
        XCTAssertEqual(detail.seasons[0].episodes.map(\.id), [101, 102])
        XCTAssertEqual(detail.seasons[0].episodes[0].containerExtension, "mp4")
        XCTAssertEqual(detail.seasons[0].episodes[1].plot, "Plot")
        XCTAssertEqual(detail.seasons[0].episodes[1].durationSeconds, 2_700)
        XCTAssertEqual(detail.seasons[1].episodes[0].containerExtension, "mkv")
        XCTAssertEqual(detail.plot, "Zeitreisen.")
        XCTAssertEqual(detail.backdropURL?.absoluteString, "http://img.example/b.jpg")
        XCTAssertTrue(http.requests[0].url!.absoluteString.hasSuffix("&action=get_series_info&series_id=42"))
    }

    func testSeriesDetailAcceptsNestedListAndMissingInfo() async throws {
        let item = VODItem(kind: .series, sourceID: 42, name: "Dark")
        let (client, _) = client(["get_series_info": """
        {"info":[],"episodes":[[{"id":5,"episode_num":1,"title":"A","season":3}],[{"id":6,"episode_num":1,"title":"B"}]]}
        """])

        let detail = try await client.seriesDetail(for: item)

        XCTAssertEqual(detail.seasons.map(\.number), [1, 3])
        XCTAssertEqual(detail.seasons.flatMap(\.episodes).map(\.id), [6, 5])
        XCTAssertNil(detail.plot)
    }

    func testSeriesDetailWithoutEpisodesIsEmpty() async throws {
        let (client, _) = client(["get_series_info": #"{"info":{},"episodes":[]}"#])
        let detail = try await client.seriesDetail(for: VODItem(kind: .series, sourceID: 1, name: "X"))
        XCTAssertTrue(detail.seasons.isEmpty)
    }

    func testBuildsMovieAndEpisodeURLs() throws {
        let movie = PlaybackTarget(kind: .movie, streamID: 501, containerExtension: "mkv", title: "Heat")
        let episode = PlaybackTarget(kind: .episode, streamID: 102, containerExtension: "mp4", title: "E")
        let creds = SourceCredentials.xtream(credentials)

        XCTAssertEqual(try StreamURLResolver.mediaURL(for: movie, credentials: creds).absoluteString,
                       "http://example.com:8080/movie/anna/p%26ss%2F1/501.mkv")
        XCTAssertEqual(try StreamURLResolver.mediaURL(for: episode, credentials: creds).absoluteString,
                       "http://example.com:8080/series/anna/p%26ss%2F1/102.mp4")
    }

    func testMediaURLRejectsM3UCredentials() {
        let movie = PlaybackTarget(kind: .movie, streamID: 1, title: "X")
        XCTAssertThrowsError(try StreamURLResolver.mediaURL(for: movie, credentials: .m3uURL(credentials.serverURL))) {
            XCTAssertEqual($0 as? StreamURLError, .credentialsDoNotMatchChannel)
        }
    }
}
