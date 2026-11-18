import ARJOCore
import XCTest
@testable import ARJOUI

@MainActor
final class CarPlayModelsTests: XCTestCase {
    func testStateWithoutCarPlayIsDisconnectedEvenIfVideoFlagIsSet() {
        XCTAssertEqual(CarPlayVideoState.resolve(isConnected: false, supportsVideo: true), .disconnected)
    }

    func testConnectedWithoutVideoFallsBackToAudio() {
        let state = CarPlayVideoState.resolve(isConnected: true, supportsVideo: false)
        XCTAssertEqual(state, .connectedAudioOnly)
        XCTAssertFalse(state.presentsVideo)
    }

    func testConnectedWithVideoPresentsVideo() {
        XCTAssertTrue(CarPlayVideoState.resolve(isConnected: true, supportsVideo: true).presentsVideo)
    }

    func testRowsAreUniqueLimitedAndCarryNowTitle() {
        let a = Channel(id: "1", name: "SRF 1", source: .xtream(streamID: 1))
        let b = Channel(id: "2", name: "SRF 2", source: .xtream(streamID: 2))
        let rows = CarPlayRows.make(from: [a, a, b], limit: 5, name: { $0.name.uppercased() }, nowTitle: { $0.id == "1" ? "Tagesschau" : nil })
        XCTAssertEqual(rows.map(\.id), ["1", "2"])
        XCTAssertEqual(rows.first?.title, "SRF 1")
        XCTAssertEqual(rows.first?.subtitle, "Tagesschau")
        XCTAssertNil(rows.last?.subtitle)
        XCTAssertEqual(CarPlayRows.make(from: [a, b], limit: 1, name: { $0.name }, nowTitle: { _ in nil }).count, 1)
        XCTAssertTrue(CarPlayRows.make(from: [a], limit: 0, name: { $0.name }, nowTitle: { _ in nil }).isEmpty)
    }

    func testItemLimitFollowsSystemAndStaysShort() {
        XCTAssertEqual(CarPlayDrivingLimits.itemLimit(systemMaximum: 100), 12)
        XCTAssertEqual(CarPlayDrivingLimits.itemLimit(systemMaximum: 6), 6)
        XCTAssertEqual(CarPlayDrivingLimits.itemLimit(systemMaximum: 0), 1)
    }

    func testGlanceableTextIsShortenedAndTrimmed() {
        XCTAssertEqual(CarPlayDrivingLimits.glanceable("  SRF 1  "), "SRF 1")
        let long = String(repeating: "A", count: 80)
        let short = CarPlayDrivingLimits.glanceable(long, maxLength: 20)
        XCTAssertEqual(short.count, 20)
        XCTAssertTrue(short.hasSuffix("…"))
    }
}
