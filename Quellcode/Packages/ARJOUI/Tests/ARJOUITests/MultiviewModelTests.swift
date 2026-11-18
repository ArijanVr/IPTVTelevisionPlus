import ARJOCore
import ARJOPlayer
import AVFoundation
import XCTest
@testable import ARJOUI

@MainActor
final class MultiviewModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let store = InMemoryCredentialStore()
    private var engines: [FakeEngine] = []
    private lazy var model = MultiviewModel(profile: profile, credentialStore: store) { [unowned self] in
        let fake = FakeEngine()
        engines.append(fake)
        return HybridPlaybackEngine(primary: fake, fallback: nil, player: AVPlayer())
    }

    private func channel(_ id: Int) -> Channel {
        Channel(id: String(id), name: "Sender \(id)", source: .xtream(streamID: id))
    }

    override func setUp() {
        store.saved[profile.id] = .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))
    }

    func testAddingChannelsStartsThemAndLimitsToFour() {
        for id in 1...4 { XCTAssertTrue(model.add(channel(id))) }
        XCTAssertEqual(model.slots.count, 4)
        XCTAssertFalse(model.canAddSlot)
        XCTAssertEqual(engines.map { $0.loadedURLs.first?.lastPathComponent }, ["1.m3u8", "2.m3u8", "3.m3u8", "4.m3u8"])

        XCTAssertFalse(model.add(channel(5)))
        XCTAssertEqual(model.message, "Es sind höchstens 4 Bilder gleichzeitig möglich.")
        XCTAssertEqual(model.slots.count, 4)
    }

    func testTheSameChannelCannotRunTwice() {
        XCTAssertTrue(model.add(channel(1)))
        XCTAssertFalse(model.add(channel(1)))
        XCTAssertEqual(model.message, "Dieser Sender läuft schon im Multiview.")
        XCTAssertEqual(model.slots.count, 1)
    }

    func testOnlyOneSlotHasSoundAndTheOthersAreThrottled() {
        model.add(channel(1))
        XCTAssertFalse(model.slots[0].engine.isMuted)
        XCTAssertEqual(model.slots[0].engine.maxBitRate, 0, "ein einzelnes Bild bleibt unbegrenzt")

        model.add(channel(2))
        model.add(channel(3))
        XCTAssertEqual(model.slots.map(\.engine.isMuted), [false, true, true])
        XCTAssertEqual(model.slots.map(\.engine.maxBitRate), [0, MultiviewModel.backgroundBitRate, MultiviewModel.backgroundBitRate])

        model.setAudio(slotID: model.slots[2].id)
        XCTAssertEqual(model.slots.map(\.engine.isMuted), [true, true, false])
        XCTAssertEqual(model.slots.map(\.engine.maxBitRate), [MultiviewModel.backgroundBitRate, MultiviewModel.backgroundBitRate, 0])
    }

    func testRemovingTheSoundSlotMovesSoundToTheFirstAndRemovingTheLastUnthrottles() {
        model.add(channel(1))
        model.add(channel(2))
        model.setAudio(slotID: model.slots[1].id)

        model.remove(slotID: model.slots[1].id)

        XCTAssertEqual(model.slots.count, 1)
        XCTAssertEqual(model.audioSlotID, model.slots[0].id)
        XCTAssertFalse(model.slots[0].engine.isMuted)
        XCTAssertEqual(model.slots[0].engine.maxBitRate, 0)
        XCTAssertEqual(engines[1].stopCount, 1)
    }

    func testReplacingChangesTheStreamAndRejectsDuplicates() {
        model.add(channel(1))
        model.add(channel(2))

        model.replace(slotID: model.slots[0].id, with: channel(2))
        XCTAssertEqual(model.slots[0].channel.id, "1", "Duplikat wird abgelehnt")

        model.replace(slotID: model.slots[0].id, with: channel(9))
        XCTAssertEqual(model.slots[0].channel.id, "9")
        XCTAssertEqual(engines[0].loadedURLs.last?.lastPathComponent, "9.m3u8")
    }

    func testPresentCallsTheHookAndAddsTheChannel() {
        var willPresent = 0
        model.onWillPresent = { willPresent += 1 }

        model.present(adding: channel(3))

        XCTAssertEqual(willPresent, 1)
        XCTAssertTrue(model.isPresented)
        XCTAssertEqual(model.slots.map(\.channel.id), ["3"])
    }

    func testCloseAllStopsEverythingAndResets() {
        model.present(adding: channel(1))
        model.add(channel(2))

        model.closeAll()

        XCTAssertTrue(model.slots.isEmpty)
        XCTAssertNil(model.audioSlotID)
        XCTAssertFalse(model.isPresented)
        XCTAssertEqual(engines.map(\.stopCount), [1, 1])
    }

    func testMissingCredentialsShowAsFailedSlot() {
        store.saved[profile.id] = nil
        model.add(channel(1))
        XCTAssertEqual(model.slots[0].playback.status, .failed("Die Stream-Adresse konnte nicht ermittelt werden."))
    }

    func testLayoutFramesFillTheAreaWithoutOverlap() {
        let size = CGSize(width: 1200, height: 600)
        for layout in MultiviewLayout.allCases where !layout.overlaps {
            for count in 1...4 {
                let frames = layout.frames(count: count, in: size, focus: count - 1)
                XCTAssertEqual(frames.count, count)
                let area = frames.reduce(0) { $0 + $1.width * $1.height }
                // Keine leeren Plätze: auch bei ungerader Zahl ist die Fläche voll belegt.
                XCTAssertEqual(area, size.width * size.height, accuracy: 0.5, "\(layout) \(count)")
                for (i, a) in frames.enumerated() {
                    for b in frames[(i + 1)...] { XCTAssertTrue(a.intersection(b).isNull || a.intersection(b).width * a.intersection(b).height < 0.5) }
                }
            }
        }
    }

    func testGridWithThreePicturesSpansTheLastOneOverTheFullWidth() {
        let frames = MultiviewLayout.grid.frames(count: 3, in: CGSize(width: 1200, height: 600), focus: 0)
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 0, width: 600, height: 300))
        XCTAssertEqual(frames[1], CGRect(x: 600, y: 0, width: 600, height: 300))
        XCTAssertEqual(frames[2], CGRect(x: 0, y: 300, width: 1200, height: 300))
    }

    func testGridWithTwoPicturesUsesTheWholeScreen() {
        let landscape = MultiviewLayout.grid.frames(count: 2, in: CGSize(width: 1200, height: 600), focus: 0)
        XCTAssertEqual(landscape, [CGRect(x: 0, y: 0, width: 600, height: 600), CGRect(x: 600, y: 0, width: 600, height: 600)])
        let portrait = MultiviewLayout.grid.frames(count: 2, in: CGSize(width: 400, height: 800), focus: 0)
        XCTAssertEqual(portrait, [CGRect(x: 0, y: 0, width: 400, height: 400), CGRect(x: 0, y: 400, width: 400, height: 400)])
    }

    func testPictureInPictureFillsWithTheMainAndFloatsTheOthersInsideTheCorner() {
        let size = CGSize(width: 1600, height: 900)
        let frames = MultiviewLayout.pip.frames(count: 3, in: size, focus: 1)
        XCTAssertEqual(frames[1], CGRect(origin: .zero, size: size))
        for index in [0, 2] {
            let small = frames[index]
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(small), "\(small)")
            XCTAssertLessThan(small.width, size.width / 3)
            XCTAssertEqual(small.width / small.height, 16.0 / 9.0, accuracy: 0.01)
            XCTAssertGreaterThan(small.midX, size.width / 2)
        }
        XCTAssertTrue(frames[0].intersection(frames[2]).isNull)
        XCTAssertEqual(MultiviewLayout.pip.frames(count: 1, in: size, focus: 0), [CGRect(origin: .zero, size: size)])
    }

    func testStageLayoutPutsTheMainPictureOnTopAndTheOthersBelow() {
        let frames = MultiviewLayout.stage.frames(count: 3, in: CGSize(width: 1000, height: 500), focus: 2)
        XCTAssertEqual(frames[2], CGRect(x: 0, y: 0, width: 1000, height: 370))
        XCTAssertEqual(frames[0].minY, 370)
        XCTAssertEqual(frames[0].width, 500)
        XCTAssertEqual(frames[1].minX, 500)
    }

    func testFocusLayoutMakesTheFocusedPictureLargest() {
        let frames = MultiviewLayout.focus.frames(count: 3, in: CGSize(width: 1000, height: 500), focus: 1)
        XCTAssertGreaterThan(frames[1].width * frames[1].height, frames[0].width * frames[0].height)
        XCTAssertEqual(frames[1].width, 700)
    }
}
