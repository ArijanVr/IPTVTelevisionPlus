import ARJOCore
import XCTest
@testable import ARJONetwork

final class GzipTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arjo-gz-\(UUID())")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func gzip(_ text: String) throws -> URL {
        let plain = directory.appendingPathComponent("in.xml")
        try text.write(to: plain, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-k", plain.path]
        try process.run()
        process.waitUntilExit()
        return directory.appendingPathComponent("in.xml.gz")
    }

    func testRoundTripsLargeContentAcrossChunks() throws {
        let original = (0..<30_000).map { "<programme id=\"\($0)\">Tagesschau um \($0)</programme>" }.joined(separator: "\n")
        let packed = try gzip(original)
        XCTAssertTrue(try Gzip.isGzipped(packed))

        let unpacked = directory.appendingPathComponent("out.xml")
        try Gzip.decompress(from: packed, to: unpacked)

        XCTAssertEqual(try String(contentsOf: unpacked, encoding: .utf8), original)
    }

    func testDetectsPlainFilesAndRejectsBrokenInput() throws {
        let plain = directory.appendingPathComponent("plain.xml")
        try "<tv/>".write(to: plain, atomically: true, encoding: .utf8)
        XCTAssertFalse(try Gzip.isGzipped(plain))
        XCTAssertThrowsError(try Gzip.decompress(from: plain, to: directory.appendingPathComponent("x"))) {
            XCTAssertEqual($0 as? GzipError, .invalidHeader)
        }
    }

    func testTruncatedFileFails() throws {
        let packed = try gzip(String(repeating: "abcdefghij", count: 5_000))
        let data = try Data(contentsOf: packed)
        let cut = directory.appendingPathComponent("cut.gz")
        try data.prefix(data.count / 2).write(to: cut)

        XCTAssertThrowsError(try Gzip.decompress(from: cut, to: directory.appendingPathComponent("cut.xml")))
    }
}

final class XtreamEPGProviderTests: XCTestCase {
    private let credentials = XtreamCredentials(
        serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "p&ss")
    private let now = Date(timeIntervalSince1970: 1_792_859_400) // 2026-10-24 16:30 UTC

    private let xml = """
    <tv>
      <programme start="20261024140000 +0000" stop="20261024150000 +0000" channel="srf1.ch"><title>Zu alt</title></programme>
      <programme start="20261024160000 +0000" stop="20261024170000 +0000" channel="srf1.ch"><title>Tagesschau</title></programme>
      <programme start="20261024160000 +0000" stop="20261024170000 +0000" channel="unbekannt"><title>Fremd</title></programme>
      <programme start="20261030160000 +0000" stop="20261030170000 +0000" channel="srf1.ch"><title>Zu weit</title></programme>
    </tv>
    """

    private func collect(_ stream: AsyncThrowingStream<EPGProgramme, Error>) async throws -> [EPGProgramme] {
        var result: [EPGProgramme] = []
        for try await programme in stream { result.append(programme) }
        return result
    }

    private func provider(writing content: Data, requests: Locked<[URLRequest]>? = nil, files: Locked<[URL]>? = nil) -> XtreamEPGProvider {
        XtreamEPGProvider(credentials: credentials) { request in
            requests?.mutate { $0.append(request) }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID())")
            try content.write(to: file)
            files?.mutate { $0.append(file) }
            return file
        }
    }

    func testFiltersByChannelAndWindowAndCleansUp() async throws {
        let requests = Locked<[URLRequest]>([])
        let files = Locked<[URL]>([])
        let window = DateInterval(start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(86_400))

        let stream = try await provider(writing: Data(xml.utf8), requests: requests, files: files)
            .programmes(allowedChannelIDs: ["srf1.ch"], window: window)
        let programmes = try await collect(stream)

        XCTAssertEqual(programmes.map(\.title), ["Tagesschau"])
        XCTAssertEqual(requests.value.first?.url?.absoluteString, "http://example.com:8080/xmltv.php?username=anna&password=p%26ss")
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.value[0].path))
    }

    func testReadsGzippedDownloads() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arjo-gzp-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = dir.appendingPathComponent("epg.xml")
        try xml.write(to: plain, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-k", plain.path]
        try process.run()
        process.waitUntilExit()
        let packed = try Data(contentsOf: dir.appendingPathComponent("epg.xml.gz"))

        let window = DateInterval(start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(86_400))
        let stream = try await provider(writing: packed).programmes(allowedChannelIDs: ["srf1.ch"], window: window)

        let titles = try await collect(stream).map(\.title)
        XCTAssertEqual(titles, ["Tagesschau"])
    }

    func testMalformedXMLEndsStreamWithError() async throws {
        let window = DateInterval(start: now, end: now.addingTimeInterval(3_600))
        let stream = try await provider(writing: Data("<tv><programme></tv>".utf8))
            .programmes(allowedChannelIDs: ["a"], window: window)
        do {
            _ = try await collect(stream)
            XCTFail("Fehler erwartet")
        } catch {
            guard case XMLTVError.malformed = error else { return XCTFail("\(error)") }
        }
    }

    func testDownloadErrorIsPassedThrough() async {
        let failing = XtreamEPGProvider(credentials: credentials) { _ in throw XtreamError.invalidCredentials }
        do {
            _ = try await failing.programmes(allowedChannelIDs: [], window: DateInterval(start: now, duration: 1))
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? XtreamError, .invalidCredentials)
        }
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}
