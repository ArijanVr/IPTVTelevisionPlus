import ARJOCore
import Foundation
import Observation
import OSLog

/// Film- oder Serienliste eines Profils (je eine Instanz pro Art).
@MainActor
@Observable
public final class VODCatalogModel {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private static let rowItemLimit = 300
    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "vod")

    public let kind: VODKind
    public private(set) var phase: Phase = .loading
    public private(set) var groups: [ChannelGroup] = []
    public private(set) var isRefreshing = false
    public var refreshError: String?

    private var seriesCache: [Int: SeriesDetail] = [:]
    private let profile: Profile
    private let repository: any VODRepository
    private let credentialStore: any CredentialStore
    private let makeProvider: (XtreamCredentials) -> any VODProviding
    private let makePlaylistProvider: ((URL) -> any VODProviding)?
    private let refreshesAutomatically: @MainActor () -> Bool
    private let clock: () -> Date

    public init(
        kind: VODKind,
        profile: Profile,
        repository: any VODRepository,
        credentialStore: any CredentialStore,
        makeProvider: @escaping (XtreamCredentials) -> any VODProviding,
        refreshesAutomatically: @escaping @MainActor () -> Bool = { false },
        clock: @escaping () -> Date = { Date() },
        makePlaylistProvider: ((URL) -> any VODProviding)? = nil
    ) {
        self.makePlaylistProvider = makePlaylistProvider
        self.refreshesAutomatically = refreshesAutomatically
        self.clock = clock
        self.kind = kind
        self.profile = profile
        self.repository = repository
        self.credentialStore = credentialStore
        self.makeProvider = makeProvider
    }

    public func load() async {
        guard phase != .ready else { return }
        phase = .loading
        do {
            groups = try await repository.groups(for: profile.id, kind: kind)
            if groups.isEmpty { try await importItems() }
            phase = .ready
        } catch {
            phase = .failed(Self.message(for: error))
            return
        }
        await refreshIfStale()
    }

    private func refreshIfStale() async {
        guard refreshesAutomatically() else { return }
        do {
            if let last = try await repository.lastUpdate(for: profile.id, kind: kind),
               clock().timeIntervalSince(last) < AppSettings.autoRefreshAge { return }
        } catch {
            Self.log.error("Alter der Liste unbekannt: \(error.localizedDescription)")
            return
        }
        await refresh()
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await importItems()
        } catch {
            refreshError = Self.message(for: error)
        }
    }

    public func items(in group: ChannelGroup) async throws -> [VODItem] {
        try await repository.items(for: profile.id, kind: kind, group: group.name, limit: Self.rowItemLimit)
    }

    /// Die Episode, die nach `target` kommt (zuerst in der Staffel, dann die erste der nächsten).
    public func nextEpisode(after target: PlaybackTarget) async -> PlaybackTarget? {
        guard target.kind == .episode, let seriesID = target.seriesID else { return nil }
        let series: VODItem
        do {
            series = try await repository.item(for: profile.id, kind: .series, sourceID: seriesID)
                ?? VODItem(kind: .series, sourceID: seriesID, name: target.seriesName ?? "", groupName: target.groupName ?? Channel.ungroupedName)
        } catch {
            Self.log.error("Serie nicht gelesen: \(error.localizedDescription)")
            return nil
        }
        let detail: SeriesDetail
        if let cached = seriesCache[seriesID] {
            detail = cached
        } else {
            do {
                detail = try await seriesDetail(for: series)
            } catch {
                Self.log.error("Episodenliste nicht geladen: \(error.localizedDescription)")
                return nil
            }
            seriesCache[seriesID] = detail
        }
        let episodes = detail.seasons.sorted { $0.number < $1.number }.flatMap(\.episodes)
        guard let index = episodes.firstIndex(where: { $0.id == target.streamID }), episodes.indices.contains(index + 1) else {
            return nil
        }
        return episodes[index + 1].target(in: series)
    }

    public func movieDetail(for item: VODItem) async throws -> MovieDetail {
        try await provider().movieDetail(for: item)
    }

    public func seriesDetail(for item: VODItem) async throws -> SeriesDetail {
        try await provider().seriesDetail(for: item)
    }

    private func importItems() async throws {
        let items = try await provider().vodItems(kind: kind)
        try await repository.importItems(for: profile.id, kind: kind, from: .from(items))
        groups = try await repository.groups(for: profile.id, kind: kind)
    }

    private func provider() throws -> any VODProviding {
        guard let credentials = try credentialStore.load(for: profile.id) else { throw LiveTVError.missingCredentials }
        switch credentials {
        case .xtream(let xtream):
            return makeProvider(xtream)
        case .m3uURL(let url):
            guard let makePlaylistProvider else { throw LiveTVError.unsupportedSource }
            return makePlaylistProvider(url)
        }
    }

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(localized: "Die Inhalte konnten nicht geladen werden.")
    }
}
