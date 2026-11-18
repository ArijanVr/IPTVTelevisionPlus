import AVFoundation
import Observation
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

/// Wählt pro URL die Engine: AVPlayer für Formate, die Apple abspielt, sonst die Fallback-Engine (VLCKit).
/// Scheitert der AVPlayer an einer URL, wechselt der Neuversuch des `PlaybackController` auf die Fallback-Engine.
@MainActor
@Observable
public final class HybridPlaybackEngine: PlaybackEngine {
    public enum Backend: Equatable {
        case avPlayer
        case fallback
    }

    /// Endungen, die AVPlayer zuverlässig abspielt. Alles andere (mkv, avi, ts …) geht an die Fallback-Engine.
    static let nativeExtensions: Set<String> = ["mp4", "m4v", "mov", "m3u8", "m3u", "mp3", "m4a", "aac", "wav", "caf"]

    public private(set) var backend: Backend = .avPlayer
    public let player: AVPlayer
    public let events: AsyncStream<PlaybackEvent>
    /// Gilt für den AVPlayer; die Fallback-Engine füllt das Bild immer passend ein.
    public var aspect: PlayerAspect = .fit
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []
    public var isMuted = false {
        didSet {
            primary.isMuted = isMuted
            fallback?.isMuted = isMuted
        }
    }
    public var volume: Float = 1 {
        didSet {
            primary.volume = volume
            fallback?.volume = volume
        }
    }
    public var maxBitRate: Double = 0 {
        didSet {
            primary.maxBitRate = maxBitRate
            fallback?.maxBitRate = maxBitRate
        }
    }
    public var bufferDuration: TimeInterval = 0 {
        didSet {
            primary.bufferDuration = bufferDuration
            fallback?.bufferDuration = bufferDuration
        }
    }

    @ObservationIgnored private let primary: any PlaybackEngine
    @ObservationIgnored private let fallback: (any PlaybackEngine)?
    @ObservationIgnored private let continuation: AsyncStream<PlaybackEvent>.Continuation
    /// Bleibt nach dem ersten AVPlayer-Fehler für alle weiteren URLs dieser Engine gesetzt: sonst scheitert jeder Senderwechsel
    /// erst am AVPlayer. Live- und Film-Player haben je eine eigene Engine.
    @ObservationIgnored private var preferFallback = false
    @ObservationIgnored private var lastURL: URL?
    @ObservationIgnored private var lastPosition: TimeInterval?
    @ObservationIgnored private var forwardTasks: [Task<Void, Never>] = []

    public init(primary: any PlaybackEngine, fallback: (any PlaybackEngine)?, player: AVPlayer) {
        self.primary = primary
        self.fallback = fallback
        self.player = player
        (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self, bufferingPolicy: .bufferingNewest(16))
        forward(primary, from: .avPlayer)
        if let fallback { forward(fallback, from: .fallback) }
    }

    deinit {
        forwardTasks.forEach { $0.cancel() }
        continuation.finish()
    }

    /// AVPlayer plus VLCKit (wo verfügbar).
    public static func makeDefault() -> HybridPlaybackEngine {
        let native = AVPlayerEngine()
        #if canImport(VLCKitSPM)
        return HybridPlaybackEngine(primary: native, fallback: VLCEngine(), player: native.player)
        #else
        return HybridPlaybackEngine(primary: native, fallback: nil, player: native.player)
        #endif
    }

    /// `true`, wenn eine Fallback-Engine eingebunden ist.
    public var hasFallback: Bool { fallback != nil }

    public func load(_ url: URL, startingAt position: TimeInterval?) {
        lastURL = url
        lastPosition = position

        let next = Self.backend(for: url, preferFallback: preferFallback, hasFallback: hasFallback)
        if next != backend { engine(for: backend)?.stop() }
        backend = next
        engine(for: next)?.load(url, startingAt: position)
    }

    public func stop() {
        primary.stop()
        fallback?.stop()
        audioTracks = []
        subtitleTracks = []
    }

    /// Liest die Spuren der gerade aktiven Engine neu ein.
    public func refreshTracks() async {
        guard let active = engine(for: backend) else { return }
        await active.refreshTracks()
        audioTracks = active.audioTracks
        subtitleTracks = active.subtitleTracks
    }

    public func selectAudioTrack(_ id: Int) {
        guard let active = engine(for: backend) else { return }
        active.selectAudioTrack(id)
        audioTracks = active.audioTracks
    }

    public func selectSubtitleTrack(_ id: Int?) {
        guard let active = engine(for: backend) else { return }
        active.selectSubtitleTrack(id)
        subtitleTracks = active.subtitleTracks
    }

    static func backend(for url: URL, preferFallback: Bool, hasFallback: Bool) -> Backend {
        guard hasFallback else { return .avPlayer }
        if preferFallback { return .fallback }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || nativeExtensions.contains(ext) ? .avPlayer : .fallback
    }

    func fallbackEngine() -> (any PlaybackEngine)? { fallback }

    /// Springt um `seconds` vor (positiv) oder zurück. Nur, wenn der Stream spulbar ist (Film, Aufnahme, Live mit Zeitversatz).
    public func seek(bySeconds seconds: Int) {
        switch backend {
        case .avPlayer:
            guard let item = player.currentItem else { return }
            let target = player.currentTime().seconds + Double(seconds)
            let ranges = item.seekableTimeRanges.map(\.timeRangeValue).filter { $0.duration.seconds > 1 }
            guard let range = ranges.last else { return }
            let clamped = min(max(target, range.start.seconds), range.end.seconds - 1)
            player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        case .fallback:
            #if canImport(VLCKitSPM)
            (fallback as? VLCEngine)?.seek(bySeconds: seconds)
            #endif
        }
    }

    private func engine(for backend: Backend) -> (any PlaybackEngine)? {
        backend == .avPlayer ? primary : fallback
    }

    private func forward(_ engine: any PlaybackEngine, from source: Backend) {
        let stream = engine.events
        forwardTasks.append(Task { [weak self] in
            for await event in stream {
                self?.receive(event, from: source)
            }
        })
    }

    private func receive(_ event: PlaybackEvent, from source: Backend) {
        guard source == backend else { return }
        if case .failed = event, source == .avPlayer, hasFallback {
            preferFallback = true
            // Sofort auf VLC wechseln: der Neuversuch des Controllers wartet sonst 6 s, bevor die Fallback-Engine überhaupt startet.
            if let lastURL {
                PlaybackDiagnostics.shared.log("fallback", "avplayer failed, switching to VLC")
                load(lastURL, startingAt: lastPosition)
                return
            }
        }
        if event == .playing { Task { await refreshTracks() } }
        continuation.yield(event)
    }
}
