import Foundation
import Observation
import os

/// Lokale Wiedergabe-Diagnose (Konsole/Unified Log, Kategorie «playback»): nur Ereignisse, Fehlercodes und Zähler,
/// nie Adressen oder Zugangsdaten. Die letzten 200 Einträge stehen zusätzlich in `entries`.
@MainActor
public final class PlaybackDiagnostics {
    public static let shared = PlaybackDiagnostics()
    private let logger = Logger(subsystem: "ch.arjo.iptelevision", category: "playback")
    public private(set) var entries: [String] = []

    public func log(_ event: String, _ detail: String = "") {
        let line = detail.isEmpty ? event : "\(event) \(detail)"
        logger.info("\(line, privacy: .public)")
        entries.append("\(Date().formatted(.iso8601)) \(line)")
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }
}

/// Steuert Wiedergabe (Live und Aufnahmen) und verbindet bei Abbruch oder Stillstand automatisch neu.
/// Die Anfrage wird bei jedem Versuch neu ermittelt, damit abgelaufene Tokens ersetzt werden;
/// bei Aufnahmen setzt der Neuversuch an der zuletzt gemeldeten Position fort.
@MainActor
@Observable
public final class PlaybackController {
    public enum Status: Equatable {
        case idle
        case buffering
        case playing
        case reconnecting(attempt: Int)
        case failed(String)
        case finished
    }

    public static let liveGiveUpMessage = String(localized: "Der Sender ist nicht erreichbar.")

    public private(set) var status: Status = .idle
    @ObservationIgnored public var onProgress: ((_ position: TimeInterval, _ duration: TimeInterval) -> Void)?
    /// Nach Pause oder Spulen (sofort speichern, statt auf das nächste Intervall zu warten).
    @ObservationIgnored public var onCheckpoint: ((_ position: TimeInterval, _ duration: TimeInterval) -> Void)?
    @ObservationIgnored public var onFinished: (() -> Void)?

    @ObservationIgnored private let engine: any PlaybackEngine
    @ObservationIgnored private let policy: ReconnectPolicy
    @ObservationIgnored private let sleep: (TimeInterval) async throws -> Void
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let zapDebounce: TimeInterval
    @ObservationIgnored private var lastStart: TimeInterval = -.infinity
    @ObservationIgnored private var stableTask: Task<Void, Never>?
    @ObservationIgnored private var resolveRequest: ((TimeInterval?) throws -> PlaybackRequest)?
    @ObservationIgnored private var giveUpMessage = PlaybackController.liveGiveUpMessage
    @ObservationIgnored private var lastPosition: TimeInterval = 0
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var waitingToReload = false
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var stallTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    public init(
        engine: any PlaybackEngine,
        policy: ReconnectPolicy = ReconnectPolicy(),
        sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        /// Ruhezeit bei schnellen Senderwechseln (z. B. 0.4 für den Live-Player); 0 = sofort laden.
        zapDebounce: TimeInterval = 0
    ) {
        self.engine = engine
        self.policy = policy
        self.sleep = sleep
        self.now = now
        self.zapDebounce = zapDebounce
        let events = engine.events
        eventTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    /// Live-Wiedergabe: nur die URL wird bei jedem Versuch neu ermittelt.
    public func play(resolve: @escaping () throws -> URL) {
        start(giveUpMessage: Self.liveGiveUpMessage) { _ in PlaybackRequest(url: try resolve()) }
    }

    /// Aufnahmen: `resumeAt` ist bei einem Neuversuch die zuletzt gemeldete Position, sonst `nil`.
    public func playResumable(giveUpMessage: String, resolve: @escaping (_ resumeAt: TimeInterval?) throws -> PlaybackRequest) {
        start(giveUpMessage: giveUpMessage, resolve: resolve)
    }

    public func stop() {
        cancelTimers()
        resolveRequest = nil
        engine.stop()
        status = .idle
    }

    private func start(giveUpMessage: String, resolve: @escaping (TimeInterval?) throws -> PlaybackRequest) {
        cancelTimers()
        resolveRequest = resolve
        self.giveUpMessage = giveUpMessage
        lastPosition = 0
        attempt = 0
        status = .buffering
        // Senderwechsel kurz hintereinander (Taste gehalten): erst nach kurzer Ruhe öffnen, damit Zwischen-Sender
        // keine der oft nur einen Anbieter-Verbindung belegen.
        let current = now(), zapping = current - lastStart < 1.5
        lastStart = current
        PlaybackDiagnostics.shared.log("select", zapping ? "zapping" : "")
        guard zapping, zapDebounce > 0 else { load(); return }
        waitingToReload = true
        reconnectTask = Task { [weak self, sleep, zapDebounce] in
            do { try await sleep(zapDebounce) } catch { return }
            guard !Task.isCancelled else { return } // inzwischen ein anderer Sender gewählt
            self?.load()
        }
    }

    private func load() {
        waitingToReload = false
        guard let resolveRequest else { return }
        do {
            let request = try resolveRequest(lastPosition > 0 ? lastPosition : nil)
            engine.load(request.url, startingAt: request.startPosition)
            armStallTimer()
        } catch {
            engine.stop()
            status = .failed(String(localized: "Die Stream-Adresse konnte nicht ermittelt werden."))
        }
    }

    private func handle(_ event: PlaybackEvent) {
        switch (event, status) {
        case (_, .idle), (_, .failed), (_, .finished):
            return
        case (.progress(let position, let duration), _):
            lastPosition = position
            onProgress?(position, duration)
        case (.checkpoint(let position, let duration), _):
            lastPosition = position
            onCheckpoint?(position, duration)
        case (.finished, _):
            stallTask?.cancel()
            status = .finished
            onFinished?()
        case (.playing, _):
            stallTask?.cancel()
            if status != .playing { PlaybackDiagnostics.shared.log("playing", "attempt=\(attempt)") }
            status = .playing
            armStableTimer()
        case (.buffering, .playing), (.buffering, .buffering):
            if status == .playing { PlaybackDiagnostics.shared.log("buffering") }
            stableTask?.cancel()
            status = .buffering
            armStallTimer()
        case (.buffering, _):
            return
        case (.failed(let reason), _):
            guard !waitingToReload else { return }
            PlaybackDiagnostics.shared.log("error", Self.code(in: reason))
            scheduleReconnect()
        }
    }

    /// Setzt den Versuchszähler erst nach `stableAfter` Sekunden ununterbrochener Wiedergabe zurück.
    private func armStableTimer() {
        stableTask?.cancel()
        guard attempt > 0 else { return }
        stableTask = Task { [weak self, sleep, policy] in
            do { try await sleep(policy.stableAfter) } catch { return }
            guard let self, self.status == .playing else { return }
            PlaybackDiagnostics.shared.log("stable", "afterAttempts=\(self.attempt)")
            self.attempt = 0
        }
    }

    /// Nur der Fehlercode aus der Engine-Meldung (z. B. «Code -11800»), nie Adressen.
    static func code(in reason: String) -> String {
        if let range = reason.range(of: #"-?\d+"#, options: .regularExpression) { return "code=\(reason[range])" }
        return "code=?"
    }

    private func armStallTimer() {
        stallTask?.cancel()
        guard let timeout = policy.stallTimeout else { return }
        stallTask = Task { [weak self, sleep] in
            do { try await sleep(timeout) } catch { return }
            self?.stallElapsed()
        }
    }

    private func stallElapsed() {
        switch status {
        case .buffering, .reconnecting:
            guard !waitingToReload else { return }
            PlaybackDiagnostics.shared.log("stall")
            scheduleReconnect()
        default:
            return
        }
    }

    private func scheduleReconnect() {
        stallTask?.cancel()
        attempt += 1
        guard let delay = policy.delay(forAttempt: attempt) else {
            PlaybackDiagnostics.shared.log("giveup", "attempts=\(attempt - 1)")
            engine.stop()
            status = .failed(giveUpMessage)
            return
        }
        PlaybackDiagnostics.shared.log("retry", "attempt=\(attempt) wait=\(Int(delay))s")
        status = .reconnecting(attempt: attempt)
        waitingToReload = true
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self, sleep] in
            do { try await sleep(delay) } catch { return }
            self?.load()
        }
    }

    private func cancelTimers() {
        reconnectTask?.cancel()
        stallTask?.cancel()
        stableTask?.cancel()
        waitingToReload = false
    }
}
