import ARJOCore
import XCTest
@testable import ARJONetwork

final class M3UStreamParserTests: XCTestCase {
    private func parse(_ lines: [String]) async throws -> ([PlaylistEntry], M3UParseResult) {
        var entries: [PlaylistEntry] = []
        let stream = AsyncStream<String> { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let result = try await M3UStreamParser().parse(lines: stream) { entries.append($0) }
        return (entries, result)
    }

    func testParsesAttributesAndTitle() async throws {
        let (entries, result) = try await parse([
            "#EXTM3U",
            #"#EXTINF:-1 tvg-id="srf1.ch" tvg-name="SRF 1" tvg-logo="http://logo.example/srf1.png" group-title="Schweiz, News" catchup="default" catchup-days="3",SRF 1 HD"#,
            "http://server.example/live/user/pass/1.ts",
        ])
        XCTAssertEqual(result.entryCount, 1)
        XCTAssertEqual(entries.first?.name, "SRF 1 HD")
        XCTAssertEqual(entries.first?.tvgID, "srf1.ch")
        XCTAssertEqual(entries.first?.groupTitle, "Schweiz, News")
        XCTAssertEqual(entries.first?.logoURL?.absoluteString, "http://logo.example/srf1.png")
        XCTAssertEqual(entries.first?.catchupType, "default")
        XCTAssertEqual(entries.first?.catchupDays, 3)
        XCTAssertEqual(entries.first?.url.absoluteString, "http://server.example/live/user/pass/1.ts")
    }

    func testReadsEPGURLsFromHeader() async throws {
        let (_, result) = try await parse([
            #"#EXTM3U url-tvg="http://epg.example/a.xml, http://epg.example/b.xml""#,
        ])
        XCTAssertEqual(result.header.epgURLs.map(\.absoluteString),
                       ["http://epg.example/a.xml", "http://epg.example/b.xml"])
    }

    func testToleratesBOMAndWhitespaceAndUsesExtGrp() async throws {
        let (entries, _) = try await parse([
            "\u{FEFF}#EXTM3U",
            "",
            "#EXTINF:-1,Arte  ",
            "#EXTGRP:Kultur",
            "#EXTVLCOPT:network-caching=1000",
            "  http://server.example/arte.m3u8  ",
        ])
        XCTAssertEqual(entries.first?.name, "Arte")
        XCTAssertEqual(entries.first?.groupTitle, "Kultur")
    }

    func testFallsBackToTvgNameWhenTitleIsMissing() async throws {
        let (entries, _) = try await parse([
            "#EXTM3U",
            #"#EXTINF:-1 tvg-name="3sat","#,
            "http://server.example/3sat.ts",
        ])
        XCTAssertEqual(entries.first?.name, "3sat")
    }

    func testSkipsEntriesWithoutExtInfOrWithInvalidURL() async throws {
        let (entries, result) = try await parse([
            "#EXTM3U",
            "http://server.example/orphan.ts",
            "#EXTINF:-1,Kaputt",
            "kein url",
            "#EXTINF:-1,Gut",
            "http://server.example/gut.ts",
        ])
        XCTAssertEqual(entries.map(\.name), ["Gut"])
        XCTAssertEqual(result.skippedCount, 2)
    }

    func testThrowsWhenHeaderIsMissing() async {
        do {
            _ = try await parse(["<html>Login</html>"])
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? M3UParseError, .missingHeader)
        }
    }

    func testThrowsOnEmptyInput() async {
        do {
            _ = try await parse([])
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? M3UParseError, .missingHeader)
        }
    }

    func testParsesLargeFileFromDisk() async throws {
        let count = 50_000
        var content = "#EXTM3U\n"
        for i in 0..<count {
            content += "#EXTINF:-1 tvg-id=\"id\(i)\" group-title=\"Gruppe \(i % 50)\",Sender \(i)\n"
            content += "http://server.example/live/\(i).ts\n"
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("arjo-\(UUID()).m3u")
        try content.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        var seen = 0
        let result = try await M3UStreamParser().parse(fileURL: file) { _ in seen += 1 }
        XCTAssertEqual(result.entryCount, count)
        XCTAssertEqual(seen, count)
    }
}

final class M3UChannelNumberTests: XCTestCase {
    func testReadsTvgChno() async throws {
        var entries: [PlaylistEntry] = []
        let lines = ["#EXTM3U", #"#EXTINF:-1 tvg-chno="12" ,Testsender 1"#, "http://server.example/a.ts",
                     #"#EXTINF:-1 tvg-chno="x",Testsender 2"#, "http://server.example/b.ts"]
        let stream = AsyncStream<String> { c in lines.forEach { c.yield($0) }; c.finish() }
        _ = try await M3UStreamParser().parse(lines: stream) { entries.append($0) }
        XCTAssertEqual(entries.map(\.channelNumber), [12, nil])
        XCTAssertEqual(Channel(entry: entries[0]).sourceNumber, 12)
    }
}
