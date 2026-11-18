#if canImport(VLCKitSPM)
import Observation
#if os(macOS)
import AppKit
public typealias VLCHostingView = NSView
#else
import UIKit
public typealias VLCHostingView = UIView
#endif
import VLCKitSPM

/// Fallback-Engine auf Basis von VLCKit: spielt MKV, AVI, TS, AC3 und weitere Formate, die AVPlayer nicht kann.
@MainActor
@Observable
public final class VLCEngine: NSObject, PlaybackEngine, @preconcurrency VLCMediaPlayerDelegate {
    private static let progressInterval: TimeInterval = 5
    private static let liveStartCaching: TimeInterval = 1.5

    /// Xtream-Live (`/live/…`) und rohes `.ts`; Filme und Serien haben andere Pfade.
    static func isLive(_ url: URL) -> Bool {
        url.path.hasPrefix("/live/") || url.pathExtension.lowercased() == "ts"
    }

    public let events: AsyncStream<PlaybackEvent>
    public private(set) var isPaused = false
    public private(set) var isSeekable = false
    public private(set) var positionSeconds: TimeInterval = 0
    /// 0 bei Live-Streams.
    public private(set) var durationSeconds: TimeInterval = 0
    public private(set) var selectedAudioIndex = -1
    public private(set) var selectedSubtitleIndex = -1
    private var audioList: [(index: Int, name: String)] = []
    private var subtitleList: [(index: Int, name: String)] = []

    public var audioTracks: [MediaTrack] {
        audioList.map { MediaTrack(id: $0.index, name: $0.name, isSelected: $0.index == selectedAudioIndex) }
    }

    public var subtitleTracks: [MediaTrack] {
        subtitleList.map { MediaTrack(id: $0.index, name: $0.name, isSelected: $0.index == selectedSubtitleIndex) }
    }
    /// Puffer in Sekunden; höhere Werte vertragen schwächere Verbindungen. 0 = 3 s.
    @ObservationIgnored public var bufferDuration: TimeInterval = 0
    public var isMuted = false {
        didSet { player.audio?.isMuted = isMuted }
    }
    /// VLC rechnet in Prozent (100 = Normalpegel).
    public var volume: Float = 1 {
        didSet { player.audio?.volume = Int32(min(max(volume, 0), 1) * 100) }
    }

    @ObservationIgnored private let player = VLCMediaPlayer()
    @ObservationIgnored private var desiredAspect = PlayerAspect.fit
    @ObservationIgnored private var viewSize = CGSize.zero
    @ObservationIgnored private let continuation: AsyncStream<PlaybackEvent>.Continuation
    @ObservationIgnored private var pendingStartPosition: TimeInterval?
    @ObservationIgnored private var lastProgressReport = Date.distantPast
    @ObservationIgnored private var checkpointPending = false
    /// VLC meldet nach Pufferphasen oft kein erneutes «playing»; der Zeitfortschritt zeigt, dass das Bild läuft.
    @ObservationIgnored private var reportedPlaying = false

    public override init() {
        (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self, bufferingPolicy: .bufferingNewest(16))
        super.init()
        player.delegate = self
    }

    deinit {
        continuation.finish()
    }

    public func attach(to view: VLCHostingView) {
        player.drawable = view
    }

    /// «Füllen» beschneidet das Bild auf das Seitenverhältnis der Anzeige; «Einpassen» zeigt es ganz.
    public func apply(aspect: PlayerAspect, viewSize: CGSize) {
        desiredAspect = aspect
        self.viewSize = viewSize
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        if aspect == .fill {
            "\(Int(viewSize.width)):\(Int(viewSize.height))".withCString { player.videoCropGeometry = UnsafeMutablePointer(mutating: $0) }
        } else {
            player.videoCropGeometry = nil
        }
    }

    public func refreshTracks() async {
        refreshTrackLists()
    }

    public func selectAudioTrack(_ id: Int) {
        player.currentAudioTrackIndex = Int32(id)
        selectedAudioIndex = id
    }

    public func selectSubtitleTrack(_ id: Int?) {
        let index = id ?? -1
        player.currentVideoSubTitleIndex = Int32(index)
        selectedSubtitleIndex = index
    }

    public func load(_ url: URL, startingAt position: TimeInterval?) {
        pendingStartPosition = position.flatMap { $0 > 1 ? $0 : nil }
        reportedPlaying = false
        positionSeconds = 0
        durationSeconds = 0
        audioList = []
        subtitleList = []

        let media = VLCMedia(url: url)
        // Live-TS: «network-caching» ist die Wartezeit bis zum ersten Bild. 4 s Puffer hiesse 4 s schwarz bei jedem Senderwechsel,
        // darum startet Live mit höchstens `liveStartCaching`.
        var caching = bufferDuration > 0 ? bufferDuration : 3
        if Self.isLive(url) { caching = min(caching, Self.liveStartCaching) }
        media.addOptions([
            "network-caching": Int(caching * 1_000),
            "http-reconnect": true,
        ])
        player.media = media
        player.play()
        player.audio?.isMuted = isMuted
        player.audio?.volume = Int32(min(max(volume, 0), 1) * 100)
    }

    public func stop() {
        pendingStartPosition = nil
        player.stop()
        player.media = nil
        isPaused = false
    }

    public func togglePause() {
        if player.isPlaying {
            player.pause()
            isPaused = true
        } else {
            player.play()
            isPaused = false
        }
    }

    public func seek(bySeconds seconds: Int) {
        guard player.isSeekable else { return }
        if seconds >= 0 { player.jumpForward(Int32(seconds)) } else { player.jumpBackward(Int32(-seconds)) }
        checkpointPending = true
    }

    public func seek(toFraction fraction: Double) {
        guard player.isSeekable else { return }
        player.position = Float(min(max(fraction, 0), 1))
        checkpointPending = true
    }

    // MARK: VLCMediaPlayerDelegate

    public func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch player.state {
        case .opening, .buffering:
            reportedPlaying = false
            continuation.yield(.buffering)
        case .playing:
            reportedPlaying = true
            isPaused = false
            refreshTrackLists()
            applyPendingStartPosition()
            apply(aspect: desiredAspect, viewSize: viewSize)
            continuation.yield(.playing)
        case .paused:
            isPaused = true
            if durationSeconds > 0, positionSeconds > 0 {
                continuation.yield(.checkpoint(position: positionSeconds, duration: durationSeconds))
            }
        case .ended:
            // Bei Live-Streams bedeutet «Ende» einen Abbruch.
            continuation.yield(durationSeconds > 0 ? .finished : .failed("Stream beendet"))
        case .error:
            continuation.yield(.failed("Wiedergabefehler (VLC)"))
        case .stopped, .esAdded:
            break
        @unknown default:
            break
        }
    }

    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // Nur bei Änderung schreiben: @Observable meldet jeden Schreibzugriff, sonst baut SwiftUI mehrmals pro Sekunde die Steuerung neu auf.
        let position = Double(player.time.intValue) / 1_000
        let duration = Double(player.media?.length.intValue ?? 0) / 1_000
        let seekable = player.isSeekable
        if duration != durationSeconds { durationSeconds = duration }
        if seekable != isSeekable { isSeekable = seekable }
        // Bei Live (keine Dauer) zeigt niemand die Position; Aufnahmen aktualisieren sich pro ganze Sekunde.
        if duration > 0, Int(position) != Int(positionSeconds) { positionSeconds = position }
        applyPendingStartPosition()
        if !reportedPlaying, player.isPlaying {
            reportedPlaying = true
            continuation.yield(.playing)
        }

        let now = Date()
        if checkpointPending, durationSeconds > 0 {
            checkpointPending = false
            lastProgressReport = now
            continuation.yield(.checkpoint(position: positionSeconds, duration: durationSeconds))
        } else if durationSeconds > 0, now.timeIntervalSince(lastProgressReport) >= Self.progressInterval {
            lastProgressReport = now
            continuation.yield(.progress(position: positionSeconds, duration: durationSeconds))
        }
    }

    private func applyPendingStartPosition() {
        guard let start = pendingStartPosition, player.isSeekable else { return }
        pendingStartPosition = nil
        player.time = VLCTime(int: Int32(start * 1_000))
    }

    private func refreshTrackLists() {
        audioList = Self.tracks(names: player.audioTrackNames, indexes: player.audioTrackIndexes)
        subtitleList = Self.tracks(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes)
        selectedAudioIndex = Int(player.currentAudioTrackIndex)
        selectedSubtitleIndex = Int(player.currentVideoSubTitleIndex)
    }

    private static func tracks(names: [Any], indexes: [Any]) -> [(index: Int, name: String)] {
        zip(names, indexes).compactMap { name, index in
            guard let name = name as? String, let index = (index as? NSNumber)?.intValue else { return nil }
            return (index, name)
        }
    }
}
#endif
