import ARJOCore
import ARJONetwork
import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class EPGModel {
    public enum Status: Equatable {
        case idle
        case updating
        case failed(String)
    }

    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "epg")
    private static let pastWindow: TimeInterval = 6 * 3_600
    private static let futureWindow: TimeInterval = 3 * 24 * 3_600

    public private(set) var status: Status = .idle
    /// Wird nach jedem erfolgreichen Import erhöht, damit Ansichten neu laden.
    public private(set) var revision = 0
    public private(set) var nowNext: [String: NowNext] = [:]

    private let profile: Profile
    private let epg: any EPGRepository
    private let catalog: any CatalogRepository
    private let credentialStore: any CredentialStore
    private let makeProvider: (XtreamCredentials) -> any EPGProviding
    private let makePlaylistProvider: ((URL) -> any EPGProviding)?
    private let clock: () -> Date
    private let staleAfter: TimeInterval
    private let epgOffset: @MainActor () -> TimeInterval

    public init(
        profile: Profile,
        epg: any EPGRepository,
        catalog: any CatalogRepository,
        credentialStore: any CredentialStore,
        makeProvider: @escaping (XtreamCredentials) -> any EPGProviding,
        clock: @escaping () -> Date = { Date() },
        staleAfter: TimeInterval = 6 * 3_600,
        epgOffset: @escaping @MainActor () -> TimeInterval = { 0 },
        makePlaylistProvider: ((URL) -> any EPGProviding)? = nil
    ) {
        self.makePlaylistProvider = makePlaylistProvider
        self.profile = profile
        self.epg = epg
        self.catalog = catalog
        self.credentialStore = credentialStore
        self.makeProvider = makeProvider
        self.clock = clock
        self.staleAfter = staleAfter
        self.epgOffset = epgOffset
    }

    /// Aktueller EPG-Zeitversatz; Catch-up-Adressen brauchen die Zeit des Anbieters ohne diesen Versatz.
    public var timeOffset: TimeInterval { epgOffset() }

    public func nowNext(for channel: Channel) -> NowNext? {
        channel.epgChannelID.flatMap { nowNext[$0] }
    }

    public func refreshIfNeeded() async {
        guard status != .updating else { return }
        do {
            if let last = try await epg.lastUpdate(for: profile.id), clock().timeIntervalSince(last) < staleAfter {
                return
            }
        } catch {
            Self.log.error("EPG-Stand unbekannt, lade neu: \(error.localizedDescription)")
        }
        await refresh()
    }

    public func refresh() async {
        guard status != .updating else { return }
        status = .updating
        do {
            guard let credentials = try credentialStore.load(for: profile.id) else { throw LiveTVError.missingCredentials }
            let provider: any EPGProviding
            switch credentials {
            case .xtream(let xtream): provider = makeProvider(xtream)
            case .m3uURL(let url):
                guard let makePlaylistProvider else { throw LiveTVError.unsupportedSource }
                provider = makePlaylistProvider(url)
            }

            let channelIDs = try await catalog.epgChannelIDs(for: profile.id)
            if !channelIDs.isEmpty {
                let now = clock()
                let window = DateInterval(start: now.addingTimeInterval(-Self.pastWindow), end: now.addingTimeInterval(Self.futureWindow))
                let stream = try await provider.programmes(allowedChannelIDs: channelIDs, window: window)
                try await epg.importProgrammes(for: profile.id, from: stream)
                nowNext = [:]
                revision += 1
            }
            status = .idle
        } catch M3UPlaylistError.noEPGSource {
            // Playlist ohne EPG-Adresse: kein Fehler, es gibt dann einfach keinen Programmführer.
            status = .idle
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? String(localized: "Der Programmführer konnte nicht geladen werden."))
        }
    }

    /// Nach Änderung des Zeitversatzes: gespeicherte Jetzt/Danach-Werte verwerfen, Ansichten laden neu.
    public func offsetChanged() {
        nowNext = [:]
        revision += 1
    }

    public func dismissError() {
        if case .failed = status { status = .idle }
    }

    public func loadNowNext(for channels: [Channel]) async {
        let ids = Array(Set(channels.compactMap(\.epgChannelID)))
        guard !ids.isEmpty else { return }
        do {
            let offset = epgOffset()
            let result = try await epg.nowNext(for: profile.id, channelIDs: ids, at: clock().addingTimeInterval(-offset))
            for id in ids {
                nowNext[id] = result[id].map {
                    NowNext(now: $0.now?.shifted(by: offset), next: $0.next?.shifted(by: offset))
                }
            }
        } catch {
            Self.log.error("Jetzt/Danach konnte nicht geladen werden: \(error.localizedDescription)")
        }
    }

    public func programmes(for channels: [Channel], from: Date, to: Date) async throws -> [String: [EPGProgramme]] {
        let ids = Array(Set(channels.compactMap(\.epgChannelID)))
        guard !ids.isEmpty else { return [:] }
        let offset = epgOffset()
        let all = try await epg.programmes(
            for: profile.id, channelIDs: ids, from: from.addingTimeInterval(-offset), to: to.addingTimeInterval(-offset)
        )
        return Dictionary(grouping: all.map { $0.shifted(by: offset) }, by: \.channelID)
    }
}
