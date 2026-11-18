import ARJOCore
import ARJOPlayer
import Foundation

final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    var saved: [UUID: SourceCredentials] = [:]
    var failOnSave = false

    func save(_ credentials: SourceCredentials, for profileID: UUID) throws {
        if failOnSave { throw URLError(.cannotWriteToFile) }
        saved[profileID] = credentials
    }
    func load(for profileID: UUID) throws -> SourceCredentials? { saved[profileID] }
    func delete(for profileID: UUID) throws { saved[profileID] = nil }
}

final class FakeCatalog: CatalogRepository, @unchecked Sendable {
    var channelsByProfile: [UUID: [Channel]] = [:]
    var importCount = 0
    var failOnDelete = false

    func importChannels(for profileID: UUID, from stream: AsyncThrowingStream<Channel, Error>) async throws {
        var all: [Channel] = []
        for try await channel in stream { all.append(channel) }
        channelsByProfile[profileID] = all
        importCount += 1
    }

    func groups(for profileID: UUID) async throws -> [ChannelGroup] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for channel in channelsByProfile[profileID] ?? [] {
            if counts[channel.groupName] == nil { order.append(channel.groupName) }
            counts[channel.groupName, default: 0] += 1
        }
        return order.map { ChannelGroup(name: $0, channelCount: counts[$0] ?? 0) }
    }

    func channels(for profileID: UUID, group: String, limit: Int) async throws -> [Channel] {
        Array((channelsByProfile[profileID] ?? []).filter { $0.groupName == group }.prefix(limit))
    }

    func channel(id: String, for profileID: UUID) async throws -> Channel? {
        channelsByProfile[profileID]?.first { $0.id == id }
    }

    func channel(number: Int, for profileID: UUID) async throws -> Channel? {
        channelsByProfile[profileID]?.first { $0.number == number }
    }

    func firstChannel(for profileID: UUID) async throws -> Channel? {
        let all = channelsByProfile[profileID] ?? []
        return all.min { ($0.number ?? .max) < ($1.number ?? .max) } ?? all.first
    }

    func deleteCatalog(for profileID: UUID) async throws {
        if failOnDelete { throw URLError(.cannotRemoveFile) }
        channelsByProfile[profileID] = nil
    }

    func epgChannelIDs(for profileID: UUID) async throws -> Set<String> {
        Set((channelsByProfile[profileID] ?? []).compactMap(\.epgChannelID))
    }

    var searchError: Error?
    var updatedAt: Date?

    func lastUpdate(for profileID: UUID) async throws -> Date? { updatedAt }

    func searchChannels(for profileID: UUID, query: String, limit: Int) async throws -> [Channel] {
        if let searchError { throw searchError }
        return Array((channelsByProfile[profileID] ?? [])
            .filter { $0.name.localizedStandardContains(query) }.prefix(limit))
    }

    func channels(forEPGIDs ids: [String], for profileID: UUID) async throws -> [String: Channel] {
        var result: [String: Channel] = [:]
        for channel in channelsByProfile[profileID] ?? [] {
            if let id = channel.epgChannelID, ids.contains(id), result[id] == nil { result[id] = channel }
        }
        return result
    }
}

final class FakeEPG: EPGRepository, @unchecked Sendable {
    var programmesByProfile: [UUID: [EPGProgramme]] = [:]
    var updatedAt: Date?
    var importCount = 0
    var deleted: [UUID] = []

    func importProgrammes(for profileID: UUID, from stream: AsyncThrowingStream<EPGProgramme, Error>) async throws {
        var all: [EPGProgramme] = []
        for try await programme in stream { all.append(programme) }
        programmesByProfile[profileID] = all
        importCount += 1
        updatedAt = Date()
    }

    func programmes(for profileID: UUID, channelIDs: [String], from: Date, to: Date) async throws -> [EPGProgramme] {
        (programmesByProfile[profileID] ?? [])
            .filter { channelIDs.contains($0.channelID) && $0.stop > from && $0.start < to }
            .sorted { $0.start < $1.start }
    }

    func nowNext(for profileID: UUID, channelIDs: [String], at date: Date) async throws -> [String: NowNext] {
        let upcoming = try await programmes(for: profileID, channelIDs: channelIDs, from: date, to: date.addingTimeInterval(43_200))
        var result: [String: NowNext] = [:]
        for (id, list) in Dictionary(grouping: upcoming, by: \.channelID) {
            let airing = list.first.flatMap { $0.isAiring(at: date) ? $0 : nil }
            result[id] = NowNext(now: airing, next: airing == nil ? list.first : list.dropFirst().first)
        }
        return result
    }

    func lastUpdate(for profileID: UUID) async throws -> Date? { updatedAt }

    func searchProgrammes(for profileID: UUID, query: String, from: Date, to: Date, limit: Int) async throws -> [EPGProgramme] {
        Array((programmesByProfile[profileID] ?? [])
            .filter { $0.title.localizedStandardContains(query) && $0.stop > from && $0.start < to }
            .sorted { $0.start < $1.start }.prefix(limit))
    }

    func deleteEPG(for profileID: UUID) async throws {
        deleted.append(profileID)
        programmesByProfile[profileID] = nil
    }
}

final class RecordingEPGProvider: EPGProviding, @unchecked Sendable {
    var programmes: [EPGProgramme] = []
    var error: Error?
    private(set) var requests: [(ids: Set<String>, window: DateInterval)] = []

    func programmes(allowedChannelIDs: Set<String>, window: DateInterval) async throws -> AsyncThrowingStream<EPGProgramme, Error> {
        requests.append((allowedChannelIDs, window))
        if let error { throw error }
        let items = programmes
        return AsyncThrowingStream { continuation in
            items.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

final class FakeProfiles: ProfileRepository, @unchecked Sendable {
    var stored: [Profile] = []
    // Die Methoden laufen ausserhalb des Main Actors, die Tests lesen auf dem Main Actor: Zugriffe absichern.
    private let lock = NSLock()
    private var _lastChannels: [UUID: String] = [:]
    private var _liveStates: [UUID: LiveResumeState] = [:]
    var lastChannels: [UUID: String] {
        get { lock.withLock { _lastChannels } }
        set { lock.withLock { _lastChannels = newValue } }
    }
    var liveStates: [UUID: LiveResumeState] {
        get { lock.withLock { _liveStates } }
        set { lock.withLock { _liveStates = newValue } }
    }
    var failOnSave = false

    func profiles() async throws -> [Profile] { stored }
    func save(_ profile: Profile) async throws {
        if failOnSave { throw URLError(.cannotWriteToFile) }
        if let index = stored.firstIndex(where: { $0.id == profile.id }) { stored[index] = profile } else { stored.append(profile) }
    }
    func delete(id: UUID) async throws { stored.removeAll { $0.id == id } }
    func liveResumeState(for profileID: UUID) async throws -> LiveResumeState? {
        liveStates[profileID] ?? lastChannels[profileID].map { LiveResumeState(channelID: $0) }
    }
    func setLiveResumeState(_ state: LiveResumeState?, for profileID: UUID) async throws {
        lock.withLock {
            _liveStates[profileID] = state
            _lastChannels[profileID] = state?.channelID
        }
    }
}

struct StubProvider: LiveChannelProviding {
    let result: Result<[Channel], Error>
    func liveChannels() async throws -> [Channel] { try result.get() }
}

@MainActor
final class FakeEngine: PlaybackEngine {
    let events: AsyncStream<PlaybackEvent>
    private(set) var loadedURLs: [URL] = []
    private(set) var startPositions: [TimeInterval?] = []
    private(set) var stopCount = 0
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    init() { (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self) }

    func emit(_ event: PlaybackEvent) { continuation.yield(event) }

    func load(_ url: URL, startingAt position: TimeInterval?) {
        loadedURLs.append(url)
        startPositions.append(position)
    }
    func stop() { stopCount += 1 }
}

final class FakeVOD: VODRepository, @unchecked Sendable {
    var itemsByKind: [VODKind: [VODItem]] = [:]
    var updatedAt: [VODKind: Date] = [:]
    var importCount = 0

    func lastUpdate(for profileID: UUID, kind: VODKind) async throws -> Date? { updatedAt[kind] }

    func item(for profileID: UUID, kind: VODKind, sourceID: Int) async throws -> VODItem? {
        itemsByKind[kind]?.first { $0.sourceID == sourceID }
    }

    func recentItems(for profileID: UUID, kind: VODKind, limit: Int) async throws -> [VODItem] {
        Array((itemsByKind[kind] ?? []).filter { $0.addedAt != nil }.sorted { $0.addedAt! > $1.addedAt! }.prefix(limit))
    }
    var deleted: [UUID] = []

    func importItems(for profileID: UUID, kind: VODKind, from stream: AsyncThrowingStream<VODItem, Error>) async throws {
        var all: [VODItem] = []
        for try await item in stream { all.append(item) }
        itemsByKind[kind] = all
        importCount += 1
    }

    func groups(for profileID: UUID, kind: VODKind) async throws -> [ChannelGroup] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for item in itemsByKind[kind] ?? [] {
            if counts[item.groupName] == nil { order.append(item.groupName) }
            counts[item.groupName, default: 0] += 1
        }
        return order.map { ChannelGroup(name: $0, channelCount: counts[$0] ?? 0) }
    }

    func items(for profileID: UUID, kind: VODKind, group: String, limit: Int) async throws -> [VODItem] {
        Array((itemsByKind[kind] ?? []).filter { $0.groupName == group }.prefix(limit))
    }

    func deleteVOD(for profileID: UUID) async throws {
        deleted.append(profileID)
        itemsByKind = [:]
    }

    func searchItems(for profileID: UUID, kind: VODKind, query: String, limit: Int) async throws -> [VODItem] {
        Array((itemsByKind[kind] ?? []).filter { $0.name.localizedStandardContains(query) }.prefix(limit))
    }
}

final class FakeProgress: ProgressRepository, @unchecked Sendable {
    // Gespeichert wird ausserhalb des Main Actors, gelesen in den Tests auf dem Main Actor: Zugriffe absichern.
    private let lock = NSLock()
    private var _stored: [String: WatchProgress] = [:]
    private var _saved: [WatchProgress] = []
    private var _deleted: [UUID] = []
    var stored: [String: WatchProgress] {
        get { lock.withLock { _stored } }
        set { lock.withLock { _stored = newValue } }
    }
    var saved: [WatchProgress] {
        get { lock.withLock { _saved } }
        set { lock.withLock { _saved = newValue } }
    }
    var deleted: [UUID] {
        get { lock.withLock { _deleted } }
        set { lock.withLock { _deleted = newValue } }
    }

    func progress(for profileID: UUID, ids: [String]) async throws -> [String: WatchProgress] {
        stored.filter { ids.contains($0.key) }
    }

    func allProgress(for profileID: UUID) async throws -> [WatchProgress] { Array(stored.values) }

    func save(_ progress: WatchProgress, for profileID: UUID) async throws {
        lock.withLock {
            _saved.append(progress)
            _stored[progress.id] = progress
        }
    }

    func continueWatching(for profileID: UUID, limit: Int) async throws -> [WatchProgress] {
        Array(stored.values.filter { !$0.watched && $0.position > 10 }.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    func setWatched(_ watched: Bool, target: PlaybackTarget, for profileID: UUID) async throws {
        stored[target.id] = WatchProgress(target: target, position: 0, duration: 0, watched: watched)
    }

    func deleteProgress(for profileID: UUID) async throws {
        lock.withLock {
            _deleted.append(profileID)
            _stored = [:]
        }
    }
}

struct StubVODProvider: VODProviding {
    var items: [VODKind: [VODItem]] = [:]
    var movie: Result<MovieDetail, Error> = .success(MovieDetail())
    var series: Result<SeriesDetail, Error> = .success(SeriesDetail())
    var itemsError: Error?

    func vodItems(kind: VODKind) async throws -> [VODItem] {
        if let itemsError { throw itemsError }
        return items[kind] ?? []
    }
    func movieDetail(for item: VODItem) async throws -> MovieDetail { try movie.get() }
    func seriesDetail(for item: VODItem) async throws -> SeriesDetail { try series.get() }
}

final class FakeActiveProfile: ActiveProfileStore, @unchecked Sendable {
    var id: UUID?
    var activeProfileID: UUID? { id }
    func setActiveProfileID(_ id: UUID?) { self.id = id }
}

final class FakePINStore: PINStore, @unchecked Sendable {
    var pin: String?
    var failOnRead = false

    var hasPIN: Bool {
        get throws {
            if failOnRead { throw URLError(.cannotOpenFile) }
            return pin != nil
        }
    }
    func setPIN(_ pin: String) throws { self.pin = pin }
    func verify(_ pin: String) throws -> Bool {
        if failOnRead { throw URLError(.cannotOpenFile) }
        return self.pin == pin
    }
    func removePIN() throws { pin = nil }
}

struct NullSettingsRepository: SettingsRepository {
    func load() async throws -> AppSettings { AppSettings() }
    func save(_ settings: AppSettings) async throws {}
}

struct StubPlaylistSource: LiveCatalogStreaming, EPGProviding {
    var channels: [Channel] = []
    var epg: Result<[EPGProgramme], Error> = .success([])

    func channelStream() async throws -> AsyncThrowingStream<Channel, Error> { .from(channels) }

    func programmes(allowedChannelIDs: Set<String>, window: DateInterval) async throws -> AsyncThrowingStream<EPGProgramme, Error> {
        .from(try epg.get())
    }
}
