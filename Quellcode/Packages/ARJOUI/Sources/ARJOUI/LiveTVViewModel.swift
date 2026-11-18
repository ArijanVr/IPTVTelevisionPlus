import ARJOCore
import ARJONetwork
import ARJOPlayer
import AVFoundation
import Foundation
import Observation
import OSLog

enum LiveTVError: Error, LocalizedError {
    case missingCredentials
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .missingCredentials: String(localized: "Die Zugangsdaten wurden nicht gefunden. Bitte neu anmelden.")
        case .unsupportedSource: String(localized: "Diese Quelle enthält keine Filme und Serien.")
        }
    }
}

@MainActor
@Observable
public final class LiveTVViewModel {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// Zustand der Wiedergabeliste: grün = Konto aktiv und Liste ladbar, rot = Problem (mit Grund).
    public enum Health: Equatable {
        case unknown
        case ok
        case problem(String)
    }

    private static let rowChannelLimit = 300
    /// Während einer Aufnahme/Timeshift wird die Stelle höchstens so oft gespeichert; Pause, Spulen und Schliessen sofort.
    static let timeshiftSaveInterval: TimeInterval = 30
    /// Abstand zum Rand des Archivfensters: Näher am Ende des Archivs startet die Aufnahme nicht mehr zuverlässig.
    static let timeshiftArchiveMargin: TimeInterval = 300
    /// Weniger als so weit hinter live gilt als live.
    static let timeshiftLiveThreshold: TimeInterval = 60
    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "live")

    public let profile: Profile
    public let playback: PlaybackController
    public let engine: HybridPlaybackEngine
    public let epg: EPGModel

    public private(set) var phase: Phase = .loading
    public private(set) var groups: [ChannelGroup] = []
    public private(set) var lastChannel: Channel?
    /// Zuletzt gesehener Sender samt Timeshift-Stelle, wie er (auch von anderen Geräten) gespeichert wurde.
    public private(set) var resumeState: LiveResumeState?
    public private(set) var isRefreshing = false
    public var refreshError: String?
    public private(set) var health: Health = .unknown
    /// Ablaufdatum des Kontos, soweit der Anbieter es nennt (nur Xtream); `nil` = unbekannt oder unbegrenzt.
    public private(set) var accountExpiry: Date?
    public private(set) var nowPlaying: Channel?
    public private(set) var queue: [Channel] = []
    /// Gesetzt, solange eine vergangene Sendung läuft (Catch-up) statt des Live-Programms.
    public private(set) var catchupProgramme: EPGProgramme?
    public var isPlayerPresented = false

    // MARK: Zappen (Kanalnummern, Gruppenwechsel)

    /// Gruppen, die beim Zappen und Starten zählen (ohne ausgeblendete und gesperrte); von der Sitzung gesetzt.
    public var eligibleGroups: @MainActor ([ChannelGroup]) -> [ChannelGroup] = { $0 }
    /// Gruppen-Banner oben («Schweiz · 3 von 12»), nur kurz gesetzt.
    public private(set) var groupBanner: ChannelNavigator.GroupPosition?
    /// Zählt bei jedem Kanalwechsel hoch; die Ansicht zeigt dann das Kanal-Banner.
    public private(set) var bannerToken = 0
    /// Ziffern, die gerade eingegeben werden.
    public private(set) var numberEntry = ""
    public private(set) var numberMessage: String?
    public private(set) var previousChannel: Channel?
    private var navigator = ChannelNavigator(groups: [])
    private var pendingGroup: ChannelNavigator.GroupPosition?
    private var groupTask: Task<Void, Never>?
    private var groupBannerTask: Task<Void, Never>?
    private var digitTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?

    private let catalog: any CatalogRepository
    private let profiles: any ProfileRepository
    private let credentialStore: any CredentialStore
    private let makeProvider: (XtreamCredentials) -> any LiveChannelProviding
    private let makePlaylistSource: ((URL) -> any LiveCatalogStreaming)?
    private let resumesOnLaunch: @MainActor () -> Bool
    private let refreshesAutomatically: @MainActor () -> Bool
    private let clock: () -> Date
    private let serverTimeZone: ((XtreamCredentials) async -> TimeZone?)?
    private let accountInfo: ((XtreamCredentials) async -> XtreamAccountInfo?)?
    private var didAutoResume = false
    private var loadTask: Task<Void, Never>?
    /// Letzter Speichervorgang; der nächste wartet darauf, damit ein älterer Senderwechsel nie einen neueren überholt.
    private var lastStateSave: Task<Void, Never>?
    /// Anbieterzeit an Position 0 der laufenden Aufnahme; `nil` = live.
    private var timeshiftOrigin: Date?
    private var timeshiftInstant: Date?
    private var lastTimeshiftSave = Date.distantPast

    public init(
        profile: Profile,
        catalog: any CatalogRepository,
        profiles: any ProfileRepository,
        credentialStore: any CredentialStore,
        makeProvider: @escaping (XtreamCredentials) -> any LiveChannelProviding,
        playback: PlaybackController,
        engine: HybridPlaybackEngine,
        epg: EPGModel,
        resumesOnLaunch: @escaping @MainActor () -> Bool = { false },
        refreshesAutomatically: @escaping @MainActor () -> Bool = { false },
        clock: @escaping () -> Date = { Date() },
        makePlaylistSource: ((URL) -> any LiveCatalogStreaming)? = nil,
        serverTimeZone: ((XtreamCredentials) async -> TimeZone?)? = nil,
        accountInfo: ((XtreamCredentials) async -> XtreamAccountInfo?)? = nil
    ) {
        self.accountInfo = accountInfo
        self.serverTimeZone = serverTimeZone
        self.makePlaylistSource = makePlaylistSource
        self.resumesOnLaunch = resumesOnLaunch
        self.refreshesAutomatically = refreshesAutomatically
        self.clock = clock
        self.epg = epg
        self.profile = profile
        self.catalog = catalog
        self.profiles = profiles
        self.credentialStore = credentialStore
        self.makeProvider = makeProvider
        self.playback = playback
        self.engine = engine
    }

    /// Lädt die Senderliste und setzt, falls eingestellt, den letzten Sender fort (einmal pro Sitzung).
    public func start() async {
        await load()
        if !didAutoResume, phase == .ready {
            didAutoResume = true
            #if DEBUG
            // Nur Debug: `-ARJONoAutoplay YES` startet ohne Wiedergabe (Screenshots im Simulator ohne Menü-Taste).
            if UserDefaults.standard.bool(forKey: "ARJONoAutoplay") {
                await refreshIfStale()
                if health == .unknown { await checkAccount() }
                return
            }
            #endif
            // Fernsehen zuerst: Kanal 1 (kleinste Nummer) oder, wenn gewünscht, der zuletzt gesehene Sender.
            if resumesOnLaunch(), lastChannel != nil {
                await resumeLastChannel()
            } else if let first = await startChannel() {
                play(first, in: [first])
            }
        }
        await refreshIfStale()
        if health == .unknown { await checkAccount() }
    }

    private func refreshIfStale() async {
        guard phase == .ready, refreshesAutomatically() else { return }
        do {
            if let last = try await catalog.lastUpdate(for: profile.id),
               clock().timeIntervalSince(last) < AppSettings.autoRefreshAge { return }
        } catch {
            Self.log.error("Alter der Senderliste unbekannt: \(error.localizedDescription)")
            return
        }
        await refreshCatalog()
    }

    public func load() async {
        if phase == .ready { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        phase = .loading
        do {
            groups = try await catalog.groups(for: profile.id)
            if groups.isEmpty { try await importCatalog() }
            await restoreLastChannel()
            phase = .ready
            Task { await epg.refreshIfNeeded() }
        } catch {
            phase = .failed(Self.message(for: error))
            health = .problem(Self.message(for: error))
        }
    }

    public func refreshCatalog() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await importCatalog()
        } catch {
            refreshError = Self.message(for: error)
            health = .problem(Self.message(for: error))
            return
        }
        await checkAccount()
    }

    /// Aktualisiert die ganze Wiedergabeliste: Senderliste, Kontostatus und Programmführer.
    public func refreshAll() async {
        await refreshCatalog()
        await epg.refresh()
    }

    /// Prüft das Konto beim Anbieter (Status, Ablaufdatum). M3U-Listen haben kein Konto: dort zählt, dass sich die Liste laden lässt.
    private func checkAccount() async {
        guard let credentials = try? credentialStore.load(for: profile.id) else {
            health = .problem(Self.message(for: LiveTVError.missingCredentials))
            return
        }
        guard case .xtream(let xtream) = credentials, let accountInfo else {
            health = .ok
            return
        }
        guard let info = await accountInfo(xtream) else {
            health = .problem(String(localized: "Der Anbieter ist nicht erreichbar."))
            return
        }
        accountExpiry = info.expirationDate
        if let expiry = info.expirationDate, expiry <= clock() {
            health = .problem(String(localized: "Das Abo ist abgelaufen."))
        } else if info.status.lowercased() != "active" {
            health = .problem(String(localized: "Das Konto ist nicht aktiv."))
        } else {
            health = .ok
        }
    }

    public func channels(in group: ChannelGroup) async throws -> [Channel] {
        try await catalog.channels(for: profile.id, group: group.name, limit: Self.rowChannelLimit)
    }

    /// Sender, deren Name `query` enthält (z. B. für die Senderwahl im Multiview).
    public func searchChannels(_ query: String, limit: Int = 60) async throws -> [Channel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await catalog.searchChannels(for: profile.id, query: trimmed, limit: limit)
    }

    /// Ob `programme` auf `channel` noch als Aufnahme verfügbar ist (begonnen und innerhalb der Archivtage des Anbieters).
    public func canCatchUp(_ channel: Channel, programme: EPGProgramme) -> Bool {
        guard let days = channel.archiveDays, days > 0 else { return false }
        let now = clock()
        return programme.start <= now && programme.stop > now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// Spielt eine vergangene oder laufende Sendung von Anfang an (Catch-up/Timeshift).
    public func playCatchup(_ programme: EPGProgramme, on channel: Channel) async {
        guard canCatchUp(channel, programme: programme) else { return }
        let timeZone = await resolveServerTimeZone()
        // Angezeigte Zeiten enthalten den EPG-Zeitversatz; der Anbieter kennt nur seine eigene Zeit.
        let offset = epg.timeOffset
        let start = programme.start.addingTimeInterval(-offset)
        let end = programme.stop.addingTimeInterval(-offset)

        self.queue = queue.contains(channel) ? queue : [channel]
        nowPlaying = channel
        lastChannel = channel
        catchupProgramme = programme
        isPlayerPresented = true
        beginTimeshiftTracking(origin: start, on: channel)
        playback.play { [credentialStore, profile, clock] in
            guard let credentials = try credentialStore.load(for: profile.id) else { throw LiveTVError.missingCredentials }
            return try CatchupURLBuilder.url(
                for: channel, credentials: credentials, start: start, end: end, now: clock(), serverTimeZone: timeZone
            )
        }
    }

    /// Zurück vom Catch-up zum Live-Bild.
    public func goLive() {
        guard let nowPlaying else { return }
        catchupProgramme = nil
        endTimeshiftTracking()
        startPlayback(of: nowPlaying)
        remember(nowPlaying)
    }

    /// Setzt den zuletzt gesehenen Sender fort, auch wenn er auf einem anderen Gerät lief: an der gespeicherten
    /// Timeshift-Stelle, wenn der Sender ein Archiv hat und die Stelle noch darin liegt, sonst live.
    public func resumeLastChannel() async {
        guard let channel = lastChannel else { return }
        if let state = resumeState, state.channelID == channel.id, let instant = state.timeshiftInstant,
           canResumeTimeshift(on: channel, at: instant) {
            await playTimeshift(from: instant, on: channel)
        } else {
            play(channel, in: [channel])
        }
    }

    /// Ob die Stelle `instant` (Anbieterzeit) im Archivfenster des Senders liegt. Sender ohne Archiv können das nie.
    public func canResumeTimeshift(on channel: Channel, at instant: Date) -> Bool {
        guard let days = channel.archiveDays, days > 0 else { return false }
        let now = clock()
        let oldest = now.addingTimeInterval(-Double(days) * 86_400 + Self.timeshiftArchiveMargin)
        return instant >= oldest && instant <= now.addingTimeInterval(-Self.timeshiftLiveThreshold)
    }

    /// Spielt ab der Anbieterzeit `instant` bis jetzt (Timeshift).
    func playTimeshift(from instant: Date, on channel: Channel) async {
        let offset = epg.timeOffset
        let programme = EPGProgramme(
            channelID: channel.epgChannelID ?? channel.id,
            start: instant.addingTimeInterval(offset),
            stop: clock().addingTimeInterval(offset),
            title: String(localized: "Zeitversetzt")
        )
        await playCatchup(programme, on: channel)
    }

    /// Vergisst den zuletzt gesehenen Sender (Wiedergabeverlauf löschen).
    public func clearHistory() async {
        lastChannel = nil
        resumeState = nil
        // In dieselbe Warteschlange wie `remember`: ein bereits laufender Speichervorgang darf den gelöschten
        // Sender nicht danach wieder eintragen.
        let clearing = Task { [previous = lastStateSave, profiles, profileID = profile.id] in
            await previous?.value
            do {
                try await profiles.setLiveResumeState(nil, for: profileID)
            } catch {
                Self.log.error("Letzter Sender nicht gelöscht: \(error.localizedDescription)")
            }
        }
        lastStateSave = clearing
        await clearing.value
    }

    /// Liest den zuletzt gesehenen Sender neu (Änderung auf einem anderen Gerät), solange hier nichts läuft.
    public func refreshResumeState() async {
        guard phase == .ready, nowPlaying == nil else { return }
        await restoreLastChannel()
    }

    public func play(_ channel: Channel, in queue: [Channel], presenting: Bool = true) {
        if let current = nowPlaying, current.id != channel.id { previousChannel = current }
        bannerToken += 1
        catchupProgramme = nil
        endTimeshiftTracking()
        self.queue = queue.contains(channel) ? queue : [channel]
        nowPlaying = channel
        lastChannel = channel
        isPlayerPresented = presenting
        startPlayback(of: channel)
        remember(channel)
        Task { await epg.loadNowNext(for: [channel]) }
        if self.queue.count < 2 { Task { await fillQueueFromGroup(of: channel) } }
    }

    /// Wird nur ein einzelner Sender gestartet (Startseite, Suche), nimmt die Senderliste im Player dessen Gruppe auf.
    private func fillQueueFromGroup(of channel: Channel) async {
        guard let group = try? await channels(in: ChannelGroup(name: channel.groupName, channelCount: 0)),
              nowPlaying == channel, queue.count < 2, group.contains(channel) else { return }
        queue = group
    }

    /// Wechselt innerhalb der aktuellen Liste zum vorherigen (-1) oder nächsten (+1) Sender.
    public func playAdjacent(offset: Int) {
        guard let nowPlaying, let index = queue.firstIndex(of: nowPlaying), queue.count > 1 else { return }
        let next = queue[((index + offset) % queue.count + queue.count) % queue.count]
        play(next, in: queue)
    }

    public func retry() {
        guard let nowPlaying else { return }
        if let programme = catchupProgramme {
            Task { await playCatchup(programme, on: nowPlaying) }
        } else {
            startPlayback(of: nowPlaying)
        }
    }

    public func closePlayer() {
        cancelNumber()
        groupTask?.cancel()
        pendingGroup = nil
        groupBanner = nil
        if timeshiftOrigin != nil, let nowPlaying { saveTimeshift(on: nowPlaying) }
        endTimeshiftTracking()
        playback.stop()
        isPlayerPresented = false
        nowPlaying = nil
        catchupProgramme = nil
    }

    private func importCatalog() async throws {
        guard let credentials = try credentialStore.load(for: profile.id) else { throw LiveTVError.missingCredentials }
        let stream: AsyncThrowingStream<Channel, Error>
        switch credentials {
        case .xtream(let xtream):
            stream = .from(try await makeProvider(xtream).liveChannels())
        case .m3uURL(let url):
            guard let makePlaylistSource else { throw LiveTVError.unsupportedSource }
            stream = try await makePlaylistSource(url).channelStream()
        }
        try await catalog.importChannels(for: profile.id, from: stream)
        groups = try await catalog.groups(for: profile.id)
    }

    private var cachedServerTimeZone: TimeZone??

    private func resolveServerTimeZone() async -> TimeZone? {
        if let cached = cachedServerTimeZone { return cached }
        guard let serverTimeZone, case .xtream(let credentials)? = try? credentialStore.load(for: profile.id) else { return nil }
        let zone = await serverTimeZone(credentials)
        cachedServerTimeZone = .some(zone)
        return zone
    }

    private func startPlayback(of channel: Channel) {
        let transportStream = engine.hasFallback
        playback.play { [credentialStore, profile] in
            guard let credentials = try credentialStore.load(for: profile.id) else { throw LiveTVError.missingCredentials }
            return try StreamURLResolver.liveURL(for: channel, credentials: credentials, transportStream: transportStream)
        }
    }

    private func restoreLastChannel() async {
        do {
            guard let state = try await profiles.liveResumeState(for: profile.id) else { return }
            // Sender, die es in dieser Liste nicht (mehr) gibt, werden nicht geraten.
            guard let channel = try await catalog.channel(id: state.channelID, for: profile.id) else { return }
            resumeState = state
            lastChannel = channel
        } catch {
            Self.log.error("Letzter Sender konnte nicht geladen werden: \(error.localizedDescription)")
        }
    }

    private func remember(_ channel: Channel, timeshiftInstant: Date? = nil) {
        let state = LiveResumeState(channelID: channel.id, timeshiftInstant: timeshiftInstant, updatedAt: clock())
        resumeState = state
        lastStateSave = Task { [previous = lastStateSave, profiles, profileID = profile.id] in
            await previous?.value
            do {
                try await profiles.setLiveResumeState(state, for: profileID)
            } catch {
                Self.log.error("Letzter Sender konnte nicht gespeichert werden: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Timeshift-Stelle

    private func beginTimeshiftTracking(origin: Date, on channel: Channel) {
        timeshiftOrigin = origin
        timeshiftInstant = origin
        saveTimeshift(on: channel)
        playback.onProgress = { [weak self] position, _ in self?.timeshiftAdvanced(to: position, on: channel, immediately: false) }
        playback.onCheckpoint = { [weak self] position, _ in self?.timeshiftAdvanced(to: position, on: channel, immediately: true) }
    }

    private func endTimeshiftTracking() {
        timeshiftOrigin = nil
        timeshiftInstant = nil
        playback.onProgress = nil
        playback.onCheckpoint = nil
    }

    /// Nur Streams mit echter Zeitleiste melden Positionen; ohne Meldung bleibt die Startstelle gespeichert.
    private func timeshiftAdvanced(to position: TimeInterval, on channel: Channel, immediately: Bool) {
        guard let origin = timeshiftOrigin, position.isFinite, position >= 0 else { return }
        timeshiftInstant = origin.addingTimeInterval(position)
        if immediately || clock().timeIntervalSince(lastTimeshiftSave) >= Self.timeshiftSaveInterval {
            saveTimeshift(on: channel)
        }
    }

    private func saveTimeshift(on channel: Channel) {
        lastTimeshiftSave = clock()
        remember(channel, timeshiftInstant: timeshiftInstant)
    }

    /// Sichert die Timeshift-Stelle sofort (App geht in den Hintergrund).
    public func persistPending() {
        guard timeshiftOrigin != nil, let nowPlaying else { return }
        saveTimeshift(on: nowPlaying)
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(localized: "Die Senderliste konnte nicht geladen werden.")
    }

    // MARK: Zappen

    /// Sender mit der kleinsten Nummer in den Gruppen, die zählen.
    private func startChannel() async -> Channel? {
        let eligible = eligibleGroups(groups)
        if !eligible.isEmpty, eligible.count == groups.count,
           let first = try? await catalog.firstChannel(for: profile.id) { return first }
        var best: Channel?
        for group in eligible {
            guard let first = try? await channels(in: group).first else { continue }
            if (first.number ?? .max) < (best?.number ?? .max) || best == nil { best = first }
        }
        return best
    }

    /// Wechselt zur vorherigen (-1) oder nächsten (+1) Gruppe und startet deren ersten Sender. Schnelles Mehrfachdrücken
    /// aktualisiert nur das Banner; gestartet wird der zuletzt gewählte.
    public func switchGroup(by offset: Int) {
        let names = eligibleGroups(groups).map(\.name)
        guard !names.isEmpty else { return }
        navigator.setGroups(names)
        navigator.setCurrentGroup(pendingGroup?.name ?? nowPlaying?.groupName)
        guard let target = navigator.neighbourGroup(by: offset) else { return }
        pendingGroup = target
        groupBanner = target
        groupBannerTask?.cancel()
        groupBannerTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.groupBanner = nil
        }
        groupTask?.cancel()
        groupTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await self?.startGroup(target.name)
        }
    }

    private func startGroup(_ name: String) async {
        defer { pendingGroup = nil }
        guard let list = try? await channels(in: ChannelGroup(name: name, channelCount: 0)), let first = list.first else { return }
        guard !Task.isCancelled else { return }
        play(first, in: list)
    }

    /// Eine Ziffer der Kanalnummer; nach 2 Sekunden ohne weitere Ziffer gilt die Eingabe.
    public func enterDigit(_ digit: Int) {
        navigator.enter(digit: digit, at: clock())
        numberEntry = navigator.digits
        numberMessage = nil
        digitTask?.cancel()
        guard navigator.hasPendingDigits else { return }
        digitTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(ChannelNavigator.digitWindow)) } catch { return }
            await self?.commitNumber()
        }
    }

    /// Enter/OK: Eingabe sofort übernehmen.
    public func commitNumber() async {
        digitTask?.cancel()
        let number = navigator.commitDigits()
        numberEntry = ""
        guard let number else { return }
        await jump(toNumber: number)
    }

    public func cancelNumber() {
        digitTask?.cancel()
        navigator.cancelDigits()
        numberEntry = ""
    }

    /// Springt global zu einer Kanalnummer; liegt der Sender in der laufenden Liste, bleibt sie, sonst gilt seine Gruppe.
    private func jump(toNumber number: Int) async {
        guard let channel = try? await catalog.channel(number: number, for: profile.id),
              eligibleGroups(groups).contains(where: { $0.name == channel.groupName })
        else {
            showMessage(String(localized: "Kanal \(number) nicht vorhanden"))
            return
        }
        if channel.id == nowPlaying?.id { bannerToken += 1; return }
        if queue.contains(channel) {
            play(channel, in: queue)
        } else {
            let list = (try? await channels(in: ChannelGroup(name: channel.groupName, channelCount: 0))) ?? []
            play(channel, in: list.contains(channel) ? list : [channel])
        }
    }

    /// Neue Nummer für einen Sender (bei Konflikt tauschen). Liefert den Sender mit der neuen Nummer zurück.
    public func setNumber(_ number: Int, for channel: Channel) async -> Channel? {
        do {
            try await catalog.setNumber(number, forChannelID: channel.id, for: profile.id)
            if nowPlaying?.id == channel.id { nowPlaying = try await catalog.channel(id: channel.id, for: profile.id) }
            return try await catalog.channel(id: channel.id, for: profile.id)
        } catch {
            Self.log.error("Kanalnummer nicht geändert: \(error.localizedDescription)")
            return nil
        }
    }

    /// Nummeriert alle Sender nach den Gruppen in der gegebenen Reihenfolge neu.
    public func renumberByGroups(_ order: [String]) async {
        do {
            try await catalog.renumberByGroups(order, for: profile.id)
            if let current = nowPlaying { nowPlaying = try await catalog.channel(id: current.id, for: profile.id) }
        } catch {
            Self.log.error("Neu nummerieren fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    /// «Letzter Kanal»: zurück zum vorher gesehenen Sender.
    public func recallPreviousChannel() {
        guard let previous = previousChannel else { return }
        play(previous, in: queue.contains(previous) ? queue : [previous])
    }

    private func showMessage(_ text: String) {
        numberMessage = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.numberMessage = nil
        }
    }
}
