import XCTest
@testable import ARJOCore

final class ChannelNavigatorTests: XCTestCase {
    private func items(_ numbers: [Int]) -> [ChannelNavigator.Item] { numbers.map { .init(id: "k\($0)", number: $0) } }
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func nav() -> ChannelNavigator {
        var n = ChannelNavigator(groups: ["Schweiz", "Sport", "Kino"])
        n.load(group: "Schweiz", items: items([3, 1, 2]))
        return n
    }

    func testLoadSortsByNumberAndSelectsFirst() {
        let n = nav()
        XCTAssertEqual(n.items.map(\.number), [1, 2, 3])
        XCTAssertEqual(n.current?.number, 1)
    }

    func testZapWrapsInGroup() {
        var n = nav()
        XCTAssertEqual(n.zap(by: -1)?.number, 3)
        XCTAssertEqual(n.zap(by: 1)?.number, 1)
        XCTAssertEqual(n.zap(by: 1)?.number, 2)
    }

    func testZapSingleItemStays() {
        var n = ChannelNavigator(groups: ["A"])
        n.load(group: "A", items: items([5]))
        XCTAssertEqual(n.zap(by: 1)?.number, 5)
    }

    func testGroupStepWrapsBothWaysAndReportsPosition() {
        var n = nav()
        XCTAssertEqual(n.neighbourGroup(by: 1), .init(name: "Sport", position: 2, count: 3))
        XCTAssertEqual(n.neighbourGroup(by: -1), .init(name: "Kino", position: 3, count: 3))
        n.load(group: "Kino", items: items([30]))
        XCTAssertEqual(n.neighbourGroup(by: 1)?.name, "Schweiz")
    }

    func testGroupListWithoutHiddenOrLockedGroupsIsSkipped() {
        var n = nav()
        n.setGroups(["Schweiz", "Kino"])
        XCTAssertEqual(n.neighbourGroup(by: 1)?.name, "Kino")
    }

    func testRapidGroupStepsStartFirstChannelOfLastGroup() {
        var n = nav()
        var target = n.neighbourGroup(by: 1)!
        n.load(group: target.name, items: items([10, 11]))
        target = n.neighbourGroup(by: 1)!
        let first = n.load(group: target.name, items: items([21, 20]))
        XCTAssertEqual(first?.number, 20)
        XCTAssertEqual(n.groupPosition, .init(name: "Kino", position: 3, count: 3))
    }

    func testDigitEntryCommitsAfterWindow() {
        var n = nav()
        n.enter(digit: 1, at: t0)
        n.enter(digit: 2, at: t0.addingTimeInterval(1))
        XCTAssertEqual(n.commitDeadline, t0.addingTimeInterval(3))
        XCTAssertEqual(n.commitDigits(), 12)
        XCTAssertFalse(n.hasPendingDigits)
        XCTAssertNil(n.commitDigits())
    }

    func testDigitEntryLimits() {
        var n = nav()
        n.enter(digit: 0, at: t0)
        XCTAssertFalse(n.hasPendingDigits)
        for d in [1, 2, 3, 4, 5] { n.enter(digit: d, at: t0) }
        XCTAssertEqual(n.commitDigits(), 1234)
    }

    func testCancelClearsDigits() {
        var n = nav()
        n.enter(digit: 7, at: t0)
        n.cancelDigits()
        XCTAssertNil(n.commitDigits())
        XCTAssertNil(n.commitDeadline)
    }

    func testRecallPrevious() {
        var n = nav()
        n.zap(by: 1)
        n.zap(by: 1)
        XCTAssertEqual(n.recallPrevious()?.number, 2)
        XCTAssertEqual(n.recallPrevious()?.number, 3)
    }

    func testRecallWithoutHistoryIsNil() {
        var n = nav()
        XCTAssertNil(n.recallPrevious())
    }
}
