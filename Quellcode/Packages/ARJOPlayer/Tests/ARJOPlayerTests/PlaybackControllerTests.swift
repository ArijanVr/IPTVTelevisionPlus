import AVFoundation
import XCTest
@testable import ARJOPlayer

@MainActor
private final class FakeEngine: PlaybackEngine {
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private(set) var loadedURLs: [URL] = []
    private(set) var startPositions: [TimeInterval?] = []
    private(set) var stopCount = 0

    init() { (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self) }

    func load(_ url: URL, startingAt position: TimeInterval?) {
        loadedURLs.append(url)
        startPositions.append(position)
    }
    func stop() { stopCount += 1 }
    func emit(_ event: PlaybackEvent) { continuation.yield(event) }
}

@MainActor
final class PlaybackControllerTests: XCTestCase {
    private let url = URL(string: "http://example.com/live/1.m3u8")!

    private func makeController(
        _ engine: FakeEngine, policy: ReconnectPolicy = ReconnectPolicy(stallTimeout: nil)
    ) -> PlaybackController {
        PlaybackController(engine: engine, policy: policy, sleep: { _ in })
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, line: UInt = #line) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "Bedingung wurde nicht erreicht", line: line)
    }

    func testPlayLoadsURLAndReportsPlaying() async {
        let engine = FakeEngine()
        let controller = makeController(engine)

        controller.play { self.url }
        XCTAssertEqual(controller.status, .buffering)
        XCTAssertEqual(engine.loadedURLs, [url])

        engine.emit(.playing)
        await waitUntil { controller.status == .playing }
    }

    func testFailureReconnectsAndResolvesURLAgain() async {
        let engine = FakeEngine()
        let controller = makeController(engine)
        var resolveCount = 0
        controller.play { resolveCount += 1; return self.url }

        engine.emit(.failed("x"))
        await waitUntil { engine.loadedURLs.count == 2 }

        XCTAssertEqual(resolveCount, 2)
        XCTAssertEqual(controller.status, .reconnecting(attempt: 1))

        engine.emit(.playing)
        await waitUntil { controller.status == .playing }
    }

    func testGivesUpAfterMaxAttempts() async {
        let engine = FakeEngine()
        let controller = makeController(engine, policy: ReconnectPolicy(maxAttempts: 2, stallTimeout: nil))
        controller.play { self.url }

        for expectedLoads in 2...3 {
            engine.emit(.failed("x"))
            await waitUntil { engine.loadedURLs.count == expectedLoads }
        }
        engine.emit(.failed("x"))
        await waitUntil { controller.status == .failed("Der Sender ist nicht erreichbar.") }
        XCTAssertEqual(engine.loadedURLs.count, 3)
    }

    func testStablePlaybackResetsAttemptCounter() async {
        let engine = FakeEngine()
        let controller = makeController(engine)
        controller.play { self.url }

        engine.emit(.failed("x"))
        await waitUntil { engine.loadedURLs.count == 2 }
        engine.emit(.playing)
        await waitUntil { controller.status == .playing }
        engine.emit(.failed("y"))

        await waitUntil { controller.status == .reconnecting(attempt: 1) }
    }

    func testShortPlaybackDoesNotResetAttemptsSoFlappingStreamsEnd() async {
        let engine = FakeEngine()
        // Die 30-s-Frist für «stabil» läuft nie ab; alle anderen Wartezeiten sofort.
        let controller = PlaybackController(engine: engine, policy: ReconnectPolicy(stallTimeout: nil), sleep: { seconds in
            if seconds >= 30 { try await Task.sleep(for: .seconds(3600)) }
        })
        controller.play { self.url }
        for expectedLoads in 2...3 {
            engine.emit(.failed("x"))
            await waitUntil { engine.loadedURLs.count == expectedLoads }
            engine.emit(.playing)
            await waitUntil { controller.status == .playing }
        }
        engine.emit(.failed("x"))
        await waitUntil { controller.status == .failed("Der Sender ist nicht erreichbar.") }
        XCTAssertEqual(engine.loadedURLs.count, 3, "Erstversuch + 2 Wiederholungen, keine Endlosschleife")
    }

    func testDefaultPolicyRetriesTwiceAfterSixAndTwelveSeconds() {
        let policy = ReconnectPolicy()
        XCTAssertEqual((1...3).map { policy.delay(forAttempt: $0) }, [6, 12, nil])
        XCTAssertEqual(policy.stableAfter, 30)
    }

    func testRapidZappingLoadsOnlyTheLastChannel() async {
        let engine = FakeEngine()
        var clock: TimeInterval = 100
        var release: [CheckedContinuation<Void, Never>] = []
        let controller = PlaybackController(engine: engine, policy: ReconnectPolicy(stallTimeout: nil), sleep: { _ in
            await withCheckedContinuation { release.append($0) }
        }, now: { clock }, zapDebounce: 0.4)
        let urls = (1...4).map { URL(string: "http://example.com/live/\($0).ts")! }
        controller.play { urls[0] }
        XCTAssertEqual(engine.loadedURLs, [urls[0]], "erster Start ohne Verzögerung")
        for next in urls.dropFirst() { clock += 0.3; controller.play { next } }
        await waitUntil { release.count == 3 }
        XCTAssertEqual(engine.loadedURLs.count, 1, "Zwischen-Sender werden nicht geöffnet")
        release.forEach { $0.resume() }
        await waitUntil { engine.loadedURLs.count == 2 }
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(engine.loadedURLs.last, urls[3])
        XCTAssertEqual(engine.loadedURLs.count, 2)
    }

    func testDiagnosticsContainOnlyCodesNotAddresses() {
        XCTAssertEqual(PlaybackController.code(in: "Wiedergabefehler (Code -11800)"), "code=-11800")
        XCTAssertEqual(PlaybackController.code(in: "http://u:p@host/live/u/p/1.ts"), "code=1")
        XCTAssertEqual(PlaybackController.code(in: "kaputt"), "code=?")
    }

    func testStalledBufferingTriggersReconnectsUntilFailure() async {
        let engine = FakeEngine()
        let controller = makeController(engine, policy: ReconnectPolicy(maxAttempts: 2, stallTimeout: 20))

        controller.play { self.url }

        await waitUntil { controller.status == .failed("Der Sender ist nicht erreichbar.") }
        XCTAssertEqual(engine.loadedURLs.count, 3)
    }

    func testStopResetsAndIgnoresLateEvents() async {
        let engine = FakeEngine()
        let controller = makeController(engine)
        controller.play { self.url }

        controller.stop()
        engine.emit(.failed("spät"))
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(controller.status, .idle)
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(engine.loadedURLs.count, 1)
    }

    func testResolverFailureEndsInFailedState() {
        struct Boom: Error {}
        let engine = FakeEngine()
        let controller = makeController(engine)

        controller.play { throw Boom() }

        XCTAssertEqual(controller.status, .failed("Die Stream-Adresse konnte nicht ermittelt werden."))
        XCTAssertTrue(engine.loadedURLs.isEmpty)
    }

    func testReconnectDelaysGrowExponentiallyAndStop() {
        let policy = ReconnectPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 8)
        XCTAssertEqual((1...6).map { policy.delay(forAttempt: $0) }, [1, 2, 4, 8, 8, nil])
        XCTAssertNil(policy.delay(forAttempt: 0))
    }

    func testRecordingResumesAtLastReportedPositionAfterFailure() async {
        let engine = FakeEngine()
        let controller = makeController(engine)
        var seenResumeValues: [TimeInterval?] = []
        controller.playResumable(giveUpMessage: "Aus") { resumeAt in
            seenResumeValues.append(resumeAt)
            return PlaybackRequest(url: self.url, startPosition: resumeAt ?? 30)
        }
        XCTAssertEqual(engine.startPositions, [30])

        engine.emit(.progress(position: 125, duration: 3_000))
        await waitUntil { controller.status == .buffering && seenResumeValues.count == 1 }
        engine.emit(.failed("x"))
        await waitUntil { engine.loadedURLs.count == 2 }

        XCTAssertEqual(seenResumeValues, [nil, 125])
        XCTAssertEqual(engine.startPositions, [30, 125])
    }

    func testCheckpointIsForwardedAndUsedForReconnect() async {
        let engine = FakeEngine()
        let controller = makeController(engine)
        var checkpoints: [TimeInterval] = []
        var progressCount = 0
        controller.onCheckpoint = { position, _ in checkpoints.append(position) }
        controller.onProgress = { _, _ in progressCount += 1 }
        controller.playResumable(giveUpMessage: "x") { resumeAt in PlaybackRequest(url: self.url, startPosition: resumeAt) }
        engine.emit(.playing)

        engine.emit(.checkpoint(position: 321, duration: 1_000))
        await waitUntil { checkpoints == [321] }
        XCTAssertEqual(progressCount, 0, "Pause/Spulen meldet sich getrennt vom Intervall")

        engine.emit(.failed("x"))
        await waitUntil { engine.loadedURLs.count == 2 }
        XCTAssertEqual(engine.startPositions.last, 321, "Neuverbindung setzt an der Pause-/Spulstelle fort")
    }

    func testProgressAndFinishedAreForwarded() async {
        let engine = FakeEngine()
        let controller = makeController(engine)
        var reported: [(TimeInterval, TimeInterval)] = []
        var finished = 0
        controller.onProgress = { reported.append(($0, $1)) }
        controller.onFinished = { finished += 1 }
        controller.playResumable(giveUpMessage: "Aus") { _ in PlaybackRequest(url: self.url) }

        engine.emit(.playing)
        engine.emit(.progress(position: 5, duration: 100))
        engine.emit(.finished)
        await waitUntil { controller.status == .finished }

        XCTAssertEqual(reported.map(\.0), [5])
        XCTAssertEqual(reported.map(\.1), [100])
        XCTAssertEqual(finished, 1)
    }

    func testGiveUpMessageIsConfigurable() async {
        let engine = FakeEngine()
        let controller = makeController(engine, policy: ReconnectPolicy(maxAttempts: 0, stallTimeout: nil))
        controller.playResumable(giveUpMessage: "Format nicht unterstützt") { _ in PlaybackRequest(url: self.url) }

        engine.emit(.failed("x"))

        await waitUntil { controller.status == .failed("Format nicht unterstützt") }
    }
}

@MainActor
final class HybridPlaybackEngineTests: XCTestCase {
    private func makeEngines() -> (primary: FakeEngine, fallback: FakeEngine, hybrid: HybridPlaybackEngine) {
        let primary = FakeEngine(), fallback = FakeEngine()
        return (primary, fallback, HybridPlaybackEngine(primary: primary, fallback: fallback, player: AVPlayer()))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, line: UInt = #line) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "Bedingung wurde nicht erreicht", line: line)
    }

    func testNativeFormatsGoToAVPlayerOthersToFallback() {
        func backend(_ name: String, prefer: Bool = false, hasFallback: Bool = true) -> HybridPlaybackEngine.Backend {
            HybridPlaybackEngine.backend(for: URL(string: "http://x.example/\(name)")!, preferFallback: prefer, hasFallback: hasFallback)
        }
        XCTAssertEqual(backend("a.mp4"), .avPlayer)
        XCTAssertEqual(backend("a.M3U8"), .avPlayer)
        XCTAssertEqual(backend("a"), .avPlayer)
        XCTAssertEqual(backend("a.mkv"), .fallback)
        XCTAssertEqual(backend("a.avi"), .fallback)
        XCTAssertEqual(backend("a.ts"), .fallback)
        XCTAssertEqual(backend("a.mp4", prefer: true), .fallback)
        XCTAssertEqual(backend("a.mkv", hasFallback: false), .avPlayer)
    }

    func testLoadRoutesToTheMatchingEngineAndStopsTheOther() {
        let (primary, fallback, hybrid) = makeEngines()
        let mp4 = URL(string: "http://x.example/a.mp4")!, mkv = URL(string: "http://x.example/b.mkv")!

        hybrid.load(mp4, startingAt: nil)
        XCTAssertEqual(primary.loadedURLs, [mp4])
        XCTAssertEqual(hybrid.backend, .avPlayer)

        hybrid.load(mkv, startingAt: 42)
        XCTAssertEqual(fallback.loadedURLs, [mkv])
        XCTAssertEqual(fallback.startPositions, [42])
        XCTAssertEqual(primary.stopCount, 1)
        XCTAssertEqual(hybrid.backend, .fallback)
    }

    func testAVPlayerFailureSwitchesRetryToFallbackAndForwardsOnlyActiveEvents() async {
        let (primary, fallback, hybrid) = makeEngines()
        let controller = PlaybackController(engine: hybrid, policy: ReconnectPolicy(stallTimeout: nil), sleep: { _ in })
        let url = URL(string: "http://x.example/a.mp4")!
        controller.play { url }

        primary.emit(.failed("Codec"))
        await waitUntil { fallback.loadedURLs == [url] }
        XCTAssertEqual(hybrid.backend, .fallback)

        primary.emit(.playing) // Nachzügler der gestoppten Engine
        fallback.emit(.playing)
        await waitUntil { controller.status == .playing }
    }

    func testFallbackPreferenceStaysForLaterURLs() async {
        let (primary, fallback, hybrid) = makeEngines()
        let controller = PlaybackController(engine: hybrid, policy: ReconnectPolicy(stallTimeout: nil), sleep: { _ in })
        let first = URL(string: "http://x.example/a.mp4")!, second = URL(string: "http://x.example/b.mp4")!
        controller.play { first }
        primary.emit(.failed("x"))
        await waitUntil { hybrid.backend == .fallback }

        controller.play { second }

        XCTAssertEqual(hybrid.backend, .fallback)
        XCTAssertEqual(fallback.loadedURLs.last, second)
        XCTAssertEqual(primary.loadedURLs, [first])
    }

    func testWithoutFallbackFailuresStayOnAVPlayer() async {
        let primary = FakeEngine()
        let hybrid = HybridPlaybackEngine(primary: primary, fallback: nil, player: AVPlayer())
        let controller = PlaybackController(engine: hybrid, policy: ReconnectPolicy(stallTimeout: nil), sleep: { _ in })
        let url = URL(string: "http://x.example/a.mp4")!
        controller.play { url }

        primary.emit(.failed("x"))

        await waitUntil { primary.loadedURLs.count == 2 }
        XCTAssertEqual(hybrid.backend, .avPlayer)
    }
}

@MainActor
private final class TrackEngine: PlaybackEngine {
    let events = AsyncStream<PlaybackEvent> { _ in }
    private(set) var audioTracks = [
        MediaTrack(id: 0, name: "Deutsch", isSelected: true),
        MediaTrack(id: 1, name: "English", isSelected: false),
    ]
    private(set) var subtitleTracks = [MediaTrack(id: 0, name: "Deutsch", isSelected: false)]
    private(set) var refreshCount = 0

    func load(_ url: URL, startingAt position: TimeInterval?) {}
    func stop() {}
    func refreshTracks() async { refreshCount += 1 }

    func selectAudioTrack(_ id: Int) {
        audioTracks = audioTracks.map { MediaTrack(id: $0.id, name: $0.name, isSelected: $0.id == id) }
    }

    func selectSubtitleTrack(_ id: Int?) {
        subtitleTracks = subtitleTracks.map { MediaTrack(id: $0.id, name: $0.name, isSelected: $0.id == id) }
    }
}

@MainActor
final class TrackSelectionTests: XCTestCase {
    func testHybridMirrorsAndForwardsTrackSelectionOfTheActiveEngine() async {
        let engine = TrackEngine()
        let hybrid = HybridPlaybackEngine(primary: engine, fallback: nil, player: AVPlayer())
        XCTAssertTrue(hybrid.audioTracks.isEmpty)

        await hybrid.refreshTracks()
        XCTAssertEqual(engine.refreshCount, 1)
        XCTAssertEqual(hybrid.audioTracks.map(\.name), ["Deutsch", "English"])

        hybrid.selectAudioTrack(1)
        XCTAssertEqual(hybrid.audioTracks.filter(\.isSelected).map(\.id), [1])

        hybrid.selectSubtitleTrack(0)
        XCTAssertEqual(hybrid.subtitleTracks.first?.isSelected, true)
        hybrid.selectSubtitleTrack(nil)
        XCTAssertEqual(hybrid.subtitleTracks.first?.isSelected, false)
    }

    func testStopClearsTracks() async {
        let hybrid = HybridPlaybackEngine(primary: TrackEngine(), fallback: nil, player: AVPlayer())
        await hybrid.refreshTracks()
        hybrid.stop()
        XCTAssertTrue(hybrid.audioTracks.isEmpty)
        XCTAssertTrue(hybrid.subtitleTracks.isEmpty)
    }
}

@MainActor
private final class MuteEngine: PlaybackEngine {
    let events = AsyncStream<PlaybackEvent> { _ in }
    var isMuted = false
    var maxBitRate: Double = 0
    func load(_ url: URL, startingAt position: TimeInterval?) {}
    func stop() {}
}

@MainActor
final class MuteAndBitrateTests: XCTestCase {
    func testHybridForwardsMuteAndBitRateToBothEngines() {
        let primary = MuteEngine(), fallback = MuteEngine()
        let hybrid = HybridPlaybackEngine(primary: primary, fallback: fallback, player: AVPlayer())

        hybrid.isMuted = true
        hybrid.maxBitRate = 2_500_000

        XCTAssertTrue(primary.isMuted)
        XCTAssertTrue(fallback.isMuted)
        XCTAssertEqual(primary.maxBitRate, 2_500_000)
        XCTAssertEqual(fallback.maxBitRate, 2_500_000)
    }
}
