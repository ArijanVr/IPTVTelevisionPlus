import ARJOCore
import XCTest
@testable import ARJONetwork

final class XMLTVParserTests: XCTestCase {
    private func parse(_ xml: String) throws -> ([EPGChannel], [EPGProgramme]) {
        var channels: [EPGChannel] = []
        var programmes: [EPGProgramme] = []
        try XMLTVParser.parse(
            stream: InputStream(data: Data(xml.utf8)),
            onChannel: { channels.append($0) },
            onProgramme: { programmes.append($0) }
        )
        return (channels, programmes)
    }

    func testParsesChannelsAndProgrammes() throws {
        let (channels, programmes) = try parse("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="srf1.ch">
            <display-name>SRF 1</display-name>
            <display-name>SRF eins</display-name>
            <icon src="http://logo.example/srf1.png"/>
          </channel>
          <programme start="20261024183000 +0200" stop="20261024190000 +0200" channel="srf1.ch">
            <title lang="de">Tagesschau &amp; Wetter</title>
            <sub-title>Abendausgabe</sub-title>
            <desc>Nachrichten des Tages.</desc>
            <category>News</category>
            <icon src="http://img.example/t.jpg"/>
          </programme>
        </tv>
        """)
        XCTAssertEqual(channels, [EPGChannel(id: "srf1.ch", displayName: "SRF 1",
                                             iconURL: URL(string: "http://logo.example/srf1.png"))])
        let programme = try XCTUnwrap(programmes.first)
        XCTAssertEqual(programme.title, "Tagesschau & Wetter")
        XCTAssertEqual(programme.subtitle, "Abendausgabe")
        XCTAssertEqual(programme.category, "News")
        XCTAssertEqual(programme.iconURL?.absoluteString, "http://img.example/t.jpg")
        // 18:30 +0200 = 16:30 UTC
        XCTAssertEqual(programme.start, Date(timeIntervalSince1970: 1_792_859_400))
        XCTAssertEqual(programme.stop.timeIntervalSince(programme.start), 1_800)
    }

    func testDateWithoutOffsetIsUTCAndSecondsAreOptional() {
        XCTAssertEqual(XMLTVDate.parse("20260101000000"), Date(timeIntervalSince1970: 1_767_225_600))
        XCTAssertEqual(XMLTVDate.parse("202601010000"), Date(timeIntervalSince1970: 1_767_225_600))
        XCTAssertEqual(XMLTVDate.parse("20260101000000 -0100"), Date(timeIntervalSince1970: 1_767_229_200))
    }

    func testRejectsInvalidDates() {
        XCTAssertNil(XMLTVDate.parse("morgen"))
        XCTAssertNil(XMLTVDate.parse("20261324000000"))
        XCTAssertNil(XMLTVDate.parse("20260101000000 CET"))
    }

    func testSkipsProgrammesWithoutTitleOrValidTimes() throws {
        let (_, programmes) = try parse("""
        <tv>
          <programme start="kaputt" stop="20261024190000" channel="a"><title>A</title></programme>
          <programme start="20261024180000" stop="20261024190000" channel="a"></programme>
          <programme start="20261024180000" stop="20261024190000" channel="a"><title>B</title></programme>
        </tv>
        """)
        XCTAssertEqual(programmes.map(\.title), ["B"])
    }

    func testThrowsOnMalformedXML() {
        XCTAssertThrowsError(try parse("<tv><programme></tv>")) { error in
            guard case XMLTVError.malformed = error else { return XCTFail("falscher Fehler: \(error)") }
        }
    }
}
