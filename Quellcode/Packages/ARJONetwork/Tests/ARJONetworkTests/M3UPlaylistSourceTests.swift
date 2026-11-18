import ARJOCore
import XCTest
@testable import ARJONetwork

final class M3UPlaylistSourceTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arjo-m3u-\(UUID())")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ text: String, name: String = "list.m3u") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func collect<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
        var result: [T] = []
        for try await item in stream { result.append(item) }
        return result
    }

    func testStreamsChannelsFromLocalFileAndKeepsTheFile() async throws {
        let file = try write("""
        #EXTM3U
        #EXTINF:-1 tvg-id="srf1.ch" group-title="Schweiz",SRF 1
        http://cdn.example/srf1.m3u8
        #EXTINF:-1,Ohne Gruppe
        http://cdn.example/x.m3u8
        """)

        let channels = try await collect(try await M3UPlaylistSource(url: file).channelStream())

        XCTAssertEqual(channels.map(\.name), ["SRF 1", "Ohne Gruppe"])
        XCTAssertEqual(channels[0].groupName, "Schweiz")
        XCTAssertEqual(channels[0].epgChannelID, "srf1.ch")
        XCTAssertEqual(channels[1].groupName, Channel.ungroupedName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "lokale Dateien bleiben bestehen")
    }

    func testDownloadedPlaylistIsDeletedAfterwards() async throws {
        let downloaded = try write("#EXTM3U\n#EXTINF:-1,A\nhttp://cdn.example/a.m3u8\n", name: "downloaded.m3u")
        let source = M3UPlaylistSource(url: URL(string: "http://provider.example/list.m3u?token=abc")!) { request in
            XCTAssertEqual(request.url?.absoluteString, "http://provider.example/list.m3u?token=abc")
            return downloaded
        }

        let channels = try await collect(try await source.channelStream())

        XCTAssertEqual(channels.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path))
    }

    func testBrokenPlaylistFailsTheStream() async throws {
        let file = try write("<html>Login</html>")
        do {
            _ = try await collect(try await M3UPlaylistSource(url: file).channelStream())
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? M3UParseError, .missingHeader)
        }
    }

    func testReadHeaderFromFileReportsEPGURLsAndRejectsOtherFiles() async throws {
        let good = try write("\u{FEFF}#EXTM3U url-tvg=\"http://epg.example/guide.xml.gz\"\n#EXTINF:-1,A\nhttp://x.example/a\n")
        let header = try await M3UStreamParser.readHeader(of: good)
        XCTAssertEqual(header.epgURLs.map(\.absoluteString), ["http://epg.example/guide.xml.gz"])

        let bad = try write("hallo", name: "bad.m3u")
        do {
            _ = try await M3UStreamParser.readHeader(of: bad)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? M3UParseError, .missingHeader)
        }
    }

    func testEPGComesFromTheHeaderURLAndIsFiltered() async throws {
        let playlist = try write("#EXTM3U url-tvg=\"http://epg.example/guide.xml\"\n#EXTINF:-1,A\nhttp://x.example/a\n")
        let epg = try write("""
        <tv>
          <programme start="20261024160000 +0000" stop="20261024170000 +0000" channel="srf1.ch"><title>Tagesschau</title></programme>
          <programme start="20261024160000 +0000" stop="20261024170000 +0000" channel="fremd"><title>Fremd</title></programme>
        </tv>
        """, name: "guide.xml")
        let now = Date(timeIntervalSince1970: 1_792_859_400)
        let source = M3UPlaylistSource(url: playlist) { request in
            XCTAssertEqual(request.url?.absoluteString, "http://epg.example/guide.xml")
            return epg
        }

        let stream = try await source.programmes(allowedChannelIDs: ["srf1.ch"], window: DateInterval(start: now.addingTimeInterval(-3_600), duration: 7_200))

        let titles = try await collect(stream).map(\.title)
        XCTAssertEqual(titles, ["Tagesschau"])
    }

    func testMissingEPGSourceIsReported() async throws {
        let playlist = try write("#EXTM3U\n#EXTINF:-1,A\nhttp://x.example/a\n")
        do {
            _ = try await M3UPlaylistSource(url: playlist).programmes(allowedChannelIDs: ["a"], window: DateInterval(start: .now, duration: 60))
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? M3UPlaylistError, .noEPGSource)
        }
    }
}
