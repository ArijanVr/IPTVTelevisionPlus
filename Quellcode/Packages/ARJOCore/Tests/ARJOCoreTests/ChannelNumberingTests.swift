import XCTest
@testable import ARJOCore

final class ChannelNumberingTests: XCTestCase {
    private func c(_ id: String, _ n: Int? = nil) -> ChannelNumbering.Candidate { .init(id: id, sourceNumber: n) }

    func testSequentialFromOneInPlaylistOrder() {
        let r = ChannelNumbering.assign([c("a"), c("b"), c("c")])
        XCTAssertEqual(r.numbers, ["a": 1, "b": 2, "c": 3])
        XCTAssertEqual(r.duplicateCount, 0)
    }

    func testSourceNumbersWinAndRestFillsFreeNumbers() {
        let r = ChannelNumbering.assign([c("a"), c("b", 1), c("c", 5), c("d")])
        XCTAssertEqual(r.numbers, ["b": 1, "c": 5, "a": 2, "d": 3])
    }

    func testDuplicateSourceNumberFirstKeepsOtherGetsNextFree() {
        let r = ChannelNumbering.assign([c("a", 7), c("b", 7), c("c")])
        XCTAssertEqual(r.numbers["a"], 7)
        XCTAssertEqual(r.numbers["b"], 1)
        XCTAssertEqual(r.numbers["c"], 2)
        XCTAssertEqual(r.duplicateCount, 1)
        XCTAssertEqual(Set(r.numbers.values).count, 3)
    }

    func testUpdateKeepsExistingNumbersAndAppendsNewOnes() {
        let first = ChannelNumbering.assign([c("a"), c("b"), c("c")])
        // «b» verschwindet, «n» kommt neu dazu, die Reihenfolge ändert sich.
        let second = ChannelNumbering.assign([c("n"), c("c"), c("a")], existing: first.numbers)
        XCTAssertEqual(second.numbers["a"], 1)
        XCTAssertEqual(second.numbers["c"], 3)
        XCTAssertEqual(second.numbers["n"], 4)
        XCTAssertNil(second.numbers["b"])
    }

    func testExistingBeatsSourceNumberOfOtherChannel() {
        let r = ChannelNumbering.assign([c("x", 2), c("a")], existing: ["a": 2])
        XCTAssertEqual(r.numbers["a"], 2)
        XCTAssertNotEqual(r.numbers["x"], 2)
    }

    func testPinnedBeatsExisting() {
        let r = ChannelNumbering.assign([c("a"), c("b")], existing: ["a": 1, "b": 2], pinned: ["b": 1])
        XCTAssertEqual(r.numbers["b"], 1)
        XCTAssertNotEqual(r.numbers["a"], 1)
        XCTAssertEqual(Set(r.numbers.values).count, 2)
    }

    func testInvalidSourceNumbersAreIgnoredAndDuplicateIDsGetOneNumber() {
        let r = ChannelNumbering.assign([c("a", 0), c("a", nil), c("b", -3)])
        XCTAssertEqual(r.numbers, ["a": 1, "b": 2])
    }

    func testNumbersAreUniqueForManyChannels() {
        let list = (0..<5000).map { c("id\($0)", $0 % 7 == 0 ? 3 : nil) }
        let r = ChannelNumbering.assign(list)
        XCTAssertEqual(r.numbers.count, 5000)
        XCTAssertEqual(Set(r.numbers.values).count, 5000)
    }
}
