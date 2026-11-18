import AVFoundation

@MainActor
public final class AVPlayerEngine: PlaybackEngine {
    private static let progressInterval: TimeInterval = 5

    public let player = AVPlayer()
    public let events: AsyncStream<PlaybackEvent>
    public var bufferDuration: TimeInterval = 0
    public var maxBitRate: Double = 0 {
        didSet { player.currentItem?.preferredPeakBitRate = maxBitRate }
    }
    public var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }
    public var volume: Float {
        get { player.volume }
        set { player.volume = min(max(newValue, 0), 1) }
    }
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []

    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?

    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private var playerObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var progressToken: Any?
    private var pendingStartPosition: TimeInterval?

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self, bufferingPolicy: .bufferingNewest(16))
        playerObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.timeControlStatusChanged(status) }
        }
        progressToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: Self.progressInterval, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.reportProgress(at: time) }
        }
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        if let progressToken { player.removeTimeObserver(progressToken) }
        continuation.finish()
    }

    /// Nötig, damit Ton im Hintergrund und Bild-in-Bild auf iOS funktionieren.
    public static func configureAudioSession() throws {
        #if os(iOS) || os(tvOS)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
    }

    public func load(_ url: URL, startingAt position: TimeInterval?) {
        clearItemObservers()
        pendingStartPosition = position.flatMap { $0 > 1 ? $0 : nil }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = bufferDuration
        item.preferredPeakBitRate = maxBitRate

        itemObservation = item.observe(\.status) { [weak self] item, _ in
            let status = item.status
            let code = (item.error as NSError?)?.code ?? 0
            Task { @MainActor in self?.itemStatusChanged(status, errorCode: code) }
        }
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.continuation.yield(.buffering) }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
                let code = ((note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.code) ?? 0
                MainActor.assumeIsolated { _ = self?.continuation.yield(.failed("Wiedergabefehler (Code \(code))")) }
            },
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.continuation.yield(.finished) }
            },
            center.addObserver(forName: AVPlayerItem.timeJumpedNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportCheckpoint() }
            },
        ]

        player.replaceCurrentItem(with: item)
        player.play()
    }

    /// Liest die Audio- und Untertitelspuren des laufenden Streams.
    public func refreshTracks() async {
        guard let item = player.currentItem else {
            audioGroup = nil
            subtitleGroup = nil
            audioTracks = []
            subtitleTracks = []
            return
        }
        let asset = item.asset
        do {
            audioGroup = try await asset.loadMediaSelectionGroup(for: .audible)
            subtitleGroup = try await asset.loadMediaSelectionGroup(for: .legible)
        } catch {
            audioGroup = nil
            subtitleGroup = nil
        }
        audioTracks = Self.tracks(in: audioGroup, item: item)
        subtitleTracks = Self.tracks(in: subtitleGroup, item: item)
    }

    public func selectAudioTrack(_ id: Int) {
        guard let group = audioGroup, group.options.indices.contains(id), let item = player.currentItem else { return }
        item.select(group.options[id], in: group)
        audioTracks = Self.tracks(in: group, item: item)
    }

    public func selectSubtitleTrack(_ id: Int?) {
        guard let group = subtitleGroup, let item = player.currentItem else { return }
        if let id, group.options.indices.contains(id) {
            item.select(group.options[id], in: group)
        } else {
            item.select(nil, in: group)
        }
        subtitleTracks = Self.tracks(in: group, item: item)
    }

    private static func tracks(in group: AVMediaSelectionGroup?, item: AVPlayerItem) -> [MediaTrack] {
        guard let group else { return [] }
        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        return group.options.enumerated().map { index, option in
            MediaTrack(id: index, name: option.displayName, isSelected: option == selected)
        }
    }

    public func stop() {
        audioGroup = nil
        subtitleGroup = nil
        audioTracks = []
        subtitleTracks = []
        clearItemObservers()
        pendingStartPosition = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func clearItemObservers() {
        itemObservation = nil
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens = []
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, errorCode: Int) {
        switch status {
        case .failed:
            continuation.yield(.failed("Wiedergabefehler (Code \(errorCode))"))
        case .readyToPlay:
            guard let start = pendingStartPosition else { return }
            pendingStartPosition = nil
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        default:
            break
        }
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing: continuation.yield(.playing)
        case .waitingToPlayAtSpecifiedRate: continuation.yield(.buffering)
        case .paused: reportCheckpoint()
        @unknown default: break
        }
    }

    private func reportCheckpoint() {
        guard let duration = player.currentItem?.duration, duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else { return }
        let position = player.currentTime().seconds
        guard position.isFinite, position > 0 else { return }
        continuation.yield(.checkpoint(position: position, duration: duration.seconds))
    }

    private func reportProgress(at time: CMTime) {
        guard let duration = player.currentItem?.duration, duration.isNumeric,
              duration.seconds.isFinite, duration.seconds > 0, time.seconds.isFinite
        else { return }
        continuation.yield(.progress(position: time.seconds, duration: duration.seconds))
    }
}
