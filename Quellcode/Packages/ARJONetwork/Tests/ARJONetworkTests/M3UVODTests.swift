import ARJOCore
import XCTest
@testable import ARJONetwork

final class M3UVODTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arjo-vod-\(UUID())")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(_ name: String, _ url: String, group: String? = nil) -> PlaylistEntry {
        PlaylistEntry(name: name, url: URL(string: url)!, groupTitle: group)
    }

    func testClassifiesLiveMoviesAndEpisodes() {
        XCTAssertEqual(M3UMediaClassifier.classify(entry("SRF 1", "http://x.example/live/u/p/1.ts")), .live)
        XCTAssertEqual(M3UMediaClassifier.classify(entry("SRF 1", "http://x.example/u/p/1.m3u8")), .live)
        XCTAssertEqual(M3UMediaClassifier.classify(entry("Heat (1995)", "http://x.example/movie/u/p/55.mkv")), .movie)
        XCTAssertEqual(M3UMediaClassifier.classify(entry("Alien", "http://cdn.example/files/alien.mp4")), .movie)
        XCTAssertEqual(
            M3UMediaClassifier.classify(entry("Dark S01E02 - Lügen", "http://x.example/series/u/p/9.mkv")),
            .episode(show: "Dark", season: 1, number: 2, title: "Lügen")
        )
        XCTAssertEqual(
            M3UMediaClassifier.classify(entry("The Wire 3x07", "http://cdn.example/wire.avi")),
            .episode(show: "The Wire", season: 3, number: 7, title: nil)
        )
        XCTAssertEqual(
            M3UMediaClassifier.classify(entry("Dark.s2.e10", "http://cdn.example/dark.mp4")),
            .episode(show: "Dark", season: 2, number: 10, title: nil)
        )
        XCTAssertEqual(M3UMediaClassifier.classify(entry("Kein Name", "http://x.example/series/u/p/9")), .live,
                       "Serien-Pfad ohne erkennbare Episode: nicht raten")
    }

    func testStableIDIsDeterministicAndSpreads() {
        XCTAssertEqual(ContentIdentity.stableHash("a"), ContentIdentity.stableHash("a"))
        XCTAssertNotEqual(ContentIdentity.stableHash("a"), ContentIdentity.stableHash("b"))
        XCTAssertGreaterThan(ContentIdentity.stableHash("irgendein text"), 0)
        let ids = Set((0..<50_000).map { ContentIdentity.stableHash("http://x.example/\($0).mkv") })
        XCTAssertEqual(ids.count, 50_000, "keine Kollisionen bei 50'000 Einträgen")
    }

    private func writePlaylist() throws -> URL {
        let url = directory.appendingPathComponent("list-\(UUID()).m3u")
        try """
        #EXTM3U
        #EXTINF:-1 group-title="Schweiz",SRF 1
        http://cdn.example/live/srf1.m3u8
        #EXTINF:-1 group-title="Filme" tvg-logo="http://img.example/heat.jpg",Heat (1995)
        http://cdn.example/movie/u/p/heat.mkv
        #EXTINF:-1 group-title="Serien" tvg-logo="http://img.example/dark.jpg",Dark S01E02 - Zweite
        http://cdn.example/series/u/p/dark2.mkv
        #EXTINF:-1 group-title="Serien",Dark S01E01 - Erste
        http://cdn.example/series/u/p/dark1.mkv
        #EXTINF:-1 group-title="Serien",Dark S02E01
        http://cdn.example/series/u/p/dark3.mp4
        #EXTINF:-1 group-title="Serien",Other Show S01E01
        http://cdn.example/series/u/p/other1.mkv
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testProviderBuildsMoviesAndSeriesWithSeasonsFromTheNames() async throws {
        let provider = M3UVODProvider(url: try writePlaylist())

        let movies = try await provider.vodItems(kind: .movie)
        let series = try await provider.vodItems(kind: .series)

        XCTAssertEqual(movies.map(\.name), ["Heat (1995)"])
        XCTAssertEqual(movies[0].year, "1995")
        XCTAssertEqual(movies[0].groupName, "Filme")
        XCTAssertEqual(movies[0].containerExtension, "mkv")
        XCTAssertEqual(movies[0].streamURL?.absoluteString, "http://cdn.example/movie/u/p/heat.mkv")
        XCTAssertEqual(movies[0].posterURL?.absoluteString, "http://img.example/heat.jpg")

        XCTAssertEqual(series.map(\.name), ["Dark", "Other Show"])
        let dark = try XCTUnwrap(series.first)
        XCTAssertEqual(dark.seasons?.map(\.number), [1, 2])
        XCTAssertEqual(dark.seasons?[0].episodes.map(\.title), ["Erste", "Zweite"])
        XCTAssertEqual(dark.seasons?[1].episodes.first?.title, "Episode 1")
        XCTAssertEqual(dark.seasons?[0].episodes[0].streamURL?.lastPathComponent, "dark1.mkv")
        XCTAssertEqual(dark.posterURL?.absoluteString, "http://img.example/dark.jpg")
    }

    func testIDsAreStableAcrossReloadsAndDetailsComeFromTheItem() async throws {
        let file = try writePlaylist()
        let first = try await M3UVODProvider(url: file).vodItems(kind: .series)
        let second = try await M3UVODProvider(url: file).vodItems(kind: .series)
        XCTAssertEqual(first.map(\.sourceID), second.map(\.sourceID))

        let provider = M3UVODProvider(url: file)
        let detail = try await provider.seriesDetail(for: first[0])
        XCTAssertEqual(detail.seasons.count, 2)
        let movie = try await provider.vodItems(kind: .movie)[0]
        let movieDetail = try await provider.movieDetail(for: movie)
        XCTAssertEqual(movieDetail.containerExtension, "mkv")
    }

    func testEpisodeTargetsPlayTheirDirectURL() throws {
        let series = VODItem(kind: .series, sourceID: 7, name: "Dark", groupName: "Serien")
        let episode = Episode(id: 3, seasonNumber: 1, episodeNumber: 1, title: "Erste", streamURL: URL(string: "http://cdn.example/dark1.mkv")!)
        let url = try StreamURLResolver.mediaURL(for: episode.target(in: series), credentials: .m3uURL(URL(string: "http://cdn.example/list.m3u")!))
        XCTAssertEqual(url.absoluteString, "http://cdn.example/dark1.mkv")
    }

    func testLiveChannelStreamSkipsMoviesAndEpisodes() async throws {
        var channels: [Channel] = []
        for try await channel in try await M3UPlaylistSource(url: try writePlaylist()).channelStream() { channels.append(channel) }
        XCTAssertEqual(channels.map(\.name), ["SRF 1"])
    }
}
