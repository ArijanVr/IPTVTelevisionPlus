import ARJOCore
import ARJONetwork
import ARJOPlayer
import AVFoundation
import Foundation
import Observation
import OSLog

/// Spielt Filme und Episoden ab und hält den Wiedergabestand aktuell.
@MainActor
@Observable
public final class VODPlayerModel {
    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "vod")
    /// Ab diesem Anteil gilt ein Titel als gesehen.
    static let watchedFraction = 0.95
    /// Kürzere Positionen setzen nicht fort, sondern starten von vorn.
    static let minimumResumePosition: TimeInterval = 10
    /// Während der Wiedergabe wird höchstens so oft gespeichert (und damit an iCloud übergeben); Pause, Spulen,
    /// Schliessen, Episodenwechsel und Wechsel in den Hintergrund speichern sofort.
    static let periodicSaveInterval: TimeInterval = 30

    public let playback: PlaybackController
    public let engine: HybridPlaybackEngine
    public var isPresented = false
    public private(set) var nowPlaying: PlaybackTarget?
    /// Wird nach jedem Schliessen erhöht, damit «Weiterschauen» und Episodenlisten neu laden.
    public private(set) var progressRevision = 0
    /// Die Episode, die gleich automatisch startet.
    public private(set) var upNext: PlaybackTarget?
    /// Liefert die Folge-Episode (setzt die Sitzung, sobald die Serienliste bereitsteht).
    public var nextEpisodeProvider: ((PlaybackTarget) async -> PlaybackTarget?)?

    private let profile: Profile
    private let credentialStore: any CredentialStore
    private let progress: any ProgressRepository
    private let saveQueue: AsyncStream<WatchProgress>.Continuation
    private let autoPlayNextEpisode: @MainActor () -> Bool
    private let countdown: Duration
    private let clock: () -> Date
    private let resolveDirectURL: (PlaybackTarget) async -> URL?
    private var upNextTask: Task<Void, Never>?
    /// Letzter noch nicht gespeicherter Stand.
    private var pendingEntry: WatchProgress?
    private var lastSave = Date.distantPast

    public init(
        profile: Profile,
        credentialStore: any CredentialStore,
        progress: any ProgressRepository,
        playback: PlaybackController,
        engine: HybridPlaybackEngine,
        autoPlayNextEpisode: @escaping @MainActor () -> Bool = { true },
        countdown: Duration = .seconds(8),
        clock: @escaping () -> Date = { Date() },
        resolveDirectURL: @escaping (PlaybackTarget) async -> URL? = { _ in nil }
    ) {
        self.clock = clock
        self.resolveDirectURL = resolveDirectURL
        self.autoPlayNextEpisode = autoPlayNextEpisode
        self.countdown = countdown
        self.profile = profile
        self.credentialStore = credentialStore
        self.progress = progress
        self.playback = playback
        self.engine = engine

        // Eine Warteschlange, damit «Ende erreicht» nie vor einem älteren Zwischenstand gespeichert wird.
        let (stream, continuation) = AsyncStream.makeStream(of: WatchProgress.self)
        saveQueue = continuation
        let profileID = profile.id
        Task {
            for await entry in stream {
                do {
                    try await progress.save(entry, for: profileID)
                } catch {
                    Self.log.error("Wiedergabestand nicht gespeichert: \(error.localizedDescription)")
                }
            }
        }
    }

    deinit {
        saveQueue.finish()
    }

    /// - Parameter target: Ohne `directURL` (z. B. aus «Weiterschauen» einer Playlist-Quelle) wird die Adresse aus
    ///   dem lokalen Katalog ermittelt; der Wiedergabestand speichert sie bewusst nicht.
    public func play(_ target: PlaybackTarget) async {
        // Stand des bisherigen Titels sichern, bevor ein anderer startet (Episodenwechsel).
        persistPending()
        var target = target
        if target.directURL == nil, profile.kind == .m3u {
            target.directURL = await resolveDirectURL(target)
        }
        var saved: WatchProgress?
        do {
            saved = try await progress.progress(for: profile.id, ids: [target.id])[target.id]
        } catch {
            Self.log.error("Wiedergabestand nicht gelesen: \(error.localizedDescription)")
        }

        cancelUpNext()
        var startPosition: TimeInterval?
        if let saved, !saved.watched, saved.position > Self.minimumResumePosition,
           saved.duration == 0 || saved.position / saved.duration < Self.watchedFraction {
            startPosition = saved.position
        }

        nowPlaying = target
        isPresented = true
        playback.onProgress = { [weak self] position, duration in
            self?.record(position: position, duration: duration, target: target, immediately: false)
        }
        playback.onCheckpoint = { [weak self] position, duration in
            self?.record(position: position, duration: duration, target: target, immediately: true)
        }
        playback.onFinished = { [weak self] in self?.finish(target) }
        playback.playResumable(
            giveUpMessage: String(localized: "Die Wiedergabe ist fehlgeschlagen. Das Format (\(target.containerExtension)) wird möglicherweise noch nicht unterstützt.")
        ) { [credentialStore, profile] resumeAt in
            guard let credentials = try credentialStore.load(for: profile.id) else { throw LiveTVError.missingCredentials }
            return PlaybackRequest(
                url: try StreamURLResolver.mediaURL(for: target, credentials: credentials),
                startPosition: resumeAt ?? startPosition
            )
        }
    }

    public func retry() async {
        guard let nowPlaying else { return }
        await play(nowPlaying)
    }

    /// Startet die angekündigte nächste Episode sofort.
    public func playUpNext() async {
        guard let next = upNext else { return }
        cancelUpNext()
        await play(next)
    }

    public func cancelUpNext() {
        upNextTask?.cancel()
        upNextTask = nil
        upNext = nil
    }

    public func close() {
        cancelUpNext()
        persistPending()
        playback.stop()
        playback.onProgress = nil
        playback.onCheckpoint = nil
        playback.onFinished = nil
        isPresented = false
        nowPlaying = nil
        progressRevision += 1
    }

    public func progress(for targets: [PlaybackTarget]) async -> [String: WatchProgress] {
        do {
            return try await progress.progress(for: profile.id, ids: targets.map(\.id))
        } catch {
            Self.log.error("Wiedergabestand nicht gelesen: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Löscht den Wiedergabeverlauf dieser Quelle.
    public func clearHistory() async {
        pendingEntry = nil
        do {
            try await progress.deleteProgress(for: profile.id)
        } catch {
            Self.log.error("Wiedergabeverlauf nicht gelöscht: \(error.localizedDescription)")
        }
        progressRevision += 1
    }

    /// Lässt Listen mit Fortschritt neu laden (z. B. nach einer Änderung auf einem anderen Gerät).
    public func markProgressChanged() {
        progressRevision += 1
    }

    public func setWatched(_ watched: Bool, target: PlaybackTarget) async {
        do {
            try await progress.setWatched(watched, target: target, for: profile.id)
            progressRevision += 1
        } catch {
            Self.log.error("Gesehen-Status nicht gespeichert: \(error.localizedDescription)")
        }
    }

    /// Speichert den letzten Stand sofort (App geht in den Hintergrund, wird beendet oder unterbrochen).
    public func persistPending() {
        guard let entry = pendingEntry else { return }
        pendingEntry = nil
        lastSave = clock()
        saveQueue.yield(entry)
    }

    private func record(position: TimeInterval, duration: TimeInterval, target: PlaybackTarget, immediately: Bool) {
        guard position.isFinite, duration.isFinite else { return }
        let watched = duration > 0 && position / duration >= Self.watchedFraction
        pendingEntry = WatchProgress(
            target: Self.storable(target), position: watched ? 0 : position, duration: duration, watched: watched, updatedAt: clock()
        )
        if immediately || watched || clock().timeIntervalSince(lastSave) >= Self.periodicSaveInterval {
            persistPending()
        }
    }

    /// Ohne Stream-Adresse: Playlist-Adressen können Zugangsdaten enthalten und gehören nicht in iCloud.
    private static func storable(_ target: PlaybackTarget) -> PlaybackTarget {
        var target = target
        target.directURL = nil
        return target
    }

    private func finish(_ target: PlaybackTarget) {
        pendingEntry = nil
        lastSave = clock()
        saveQueue.yield(WatchProgress(target: Self.storable(target), position: 0, duration: 0, watched: true, updatedAt: clock()))
        progressRevision += 1

        guard target.kind == .episode, autoPlayNextEpisode(), let nextEpisodeProvider else {
            close()
            return
        }
        upNextTask = Task { [countdown] in
            guard let next = await nextEpisodeProvider(target), !Task.isCancelled else {
                if !Task.isCancelled { close() }
                return
            }
            upNext = next
            do { try await Task.sleep(for: countdown) } catch { return }
            await playUpNext()
        }
    }
}
