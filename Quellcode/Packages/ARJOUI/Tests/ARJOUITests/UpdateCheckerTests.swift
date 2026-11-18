import XCTest
@testable import ARJOUI

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.1.2", than: "1.1.1"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1.1", than: "1.1.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1", than: "1.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v1.0.9", than: "1.1.0"))
    }

    func testAvailableAndUpToDate() async {
        let json = #"{"tag_name":"v1.2.0","body":"Neu","html_url":"https://github.com/ArijanVr/IPTVTelevisionPlus/releases/tag/v1.2.0"}"#
        let newer = UpdateChecker(currentVersion: "1.1.1") { _ in Data(json.utf8) }
        await newer.check()
        guard case .available(let update) = newer.state else { return XCTFail("\(newer.state)") }
        XCTAssertEqual(update.version, "1.2.0")
        let same = UpdateChecker(currentVersion: "1.2.0") { _ in Data(json.utf8) }
        await same.check()
        XCTAssertEqual(same.state, .upToDate)
    }

    func testFailure() async {
        let checker = UpdateChecker(currentVersion: "1.0") { _ in throw URLError(.notConnectedToInternet) }
        await checker.check()
        guard case .failed = checker.state else { return XCTFail("\(checker.state)") }
    }
}
