import ARJOCore
import Foundation
import Observation

/// Globale Suche über Sender, Filme, Serien und Sendungen des laufenden und kommenden EPG.
@MainActor
@Observable
public final class SearchModel {
    public struct ProgrammeResult: Identifiable, Hashable {
        public let programme: EPGProgramme
        public let channel: Channel
        public var id: String { channel.id + "@" + String(programme.start.timeIntervalSince1970) }
    }

    public struct Results: Equatable {
        public var channels: [Channel] = []
        public var movies: [VODItem] = []
        public var series: [VODItem] = []
        public var programmes: [ProgrammeResult] = []

        public var isEmpty: Bool { channels.isEmpty && movies.isEmpty && series.isEmpty && programmes.isEmpty }
    }

    public enum State: Equatable {
        case idle
        case searching
        case done
    }

    /// Einschränkung der Ergebnisse auf einen Bereich; ändert nur die Anzeige, nicht die Suche.
    public enum Scope: String, CaseIterable, Identifiable {
        case all, live, movies, series, programmes
        public var id: Self { self }

        public var title: String {
            switch self {
            case .all: String(localized: "Alles")
            case .live: String(localized: "Live TV")
            case .movies: String(localized: "Filme")
            case .series: String(localized: "Serien")
            case .programmes: String(localized: "Sendungen")
            }
        }
    }

    public static let minimumQueryLength = 2
    public static let recentLimit = 8
    private static let resultLimit = 30
    private static let programmeLimit = 40
    private static let programmeHorizon: TimeInterval = 48 * 3_600

    public var query = ""
    public var scope: Scope = .all
    /// Zuletzt abgeschickte Suchbegriffe, neueste zuerst.
    public private(set) var recentQueries: [String] = []
    public private(set) var results = Results()
    public private(set) var state: State = .idle
    /// Gesetzt, wenn nur ein Teil der Quellen geantwortet hat.
    public private(set) var warning: String?

    private let profile: Profile
    private let catalog: any CatalogRepository
    private let vod: any VODRepository
    private let epg: any EPGRepository
    private let clock: () -> Date
    private let epgOffset: @MainActor () -> TimeInterval
    private let isLocked: @MainActor (GroupArea, String?) -> Bool
    private let history: UserDefaults?

    public init(
        profile: Profile,
        catalog: any CatalogRepository,
        vod: any VODRepository,
        epg: any EPGRepository,
        clock: @escaping () -> Date = { Date() },
        epgOffset: @escaping @MainActor () -> TimeInterval = { 0 },
        isLocked: @escaping @MainActor (GroupArea, String?) -> Bool = { _, _ in false },
        history: UserDefaults? = nil
    ) {
        self.history = history
        recentQueries = history?.stringArray(forKey: "search.recent.\(profile.id.uuidString)") ?? []
        self.isLocked = isLocked
        self.profile = profile
        self.catalog = catalog
        self.vod = vod
        self.epg = epg
        self.clock = clock
        self.epgOffset = epgOffset
    }

    public var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isQueryTooShort: Bool { trimmedQuery.count < Self.minimumQueryLength }

    /// Merkt sich den aktuellen Begriff für die Liste «Zuletzt gesucht».
    public func rememberQuery() {
        let text = trimmedQuery
        guard text.count >= Self.minimumQueryLength else { return }
        recentQueries.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        recentQueries.insert(text, at: 0)
        recentQueries = Array(recentQueries.prefix(Self.recentLimit))
        history?.set(recentQueries, forKey: "search.recent.\(profile.id.uuidString)")
    }

    public func clearRecentQueries() {
        recentQueries = []
        history?.removeObject(forKey: "search.recent.\(profile.id.uuidString)")
    }

    public func search() async {
        let text = trimmedQuery
        guard text.count >= Self.minimumQueryLength else {
            results = Results()
            warning = nil
            state = .idle
            return
        }
        state = .searching

        let profileID = profile.id, catalog = catalog, vod = vod, epg = epg, now = clock(), offset = epgOffset()
        async let channels = Self.capture { try await catalog.searchChannels(for: profileID, query: text, limit: Self.resultLimit) }
        async let movies = Self.capture { try await vod.searchItems(for: profileID, kind: .movie, query: text, limit: Self.resultLimit) }
        async let series = Self.capture { try await vod.searchItems(for: profileID, kind: .series, query: text, limit: Self.resultLimit) }
        async let programmes = Self.capture {
            let found = try await epg.searchProgrammes(
                for: profileID, query: text, from: now.addingTimeInterval(-offset),
                to: now.addingTimeInterval(Self.programmeHorizon - offset), limit: Self.programmeLimit
            )
            let byEPGID = try await catalog.channels(forEPGIDs: Array(Set(found.map(\.channelID))), for: profileID)
            return found.compactMap { programme in
                byEPGID[programme.channelID].map { ProgrammeResult(programme: programme.shifted(by: offset), channel: $0) }
            }
        }
        let (channelResult, movieResult, seriesResult, programmeResult) = await (channels, movies, series, programmes)

        // Eine neuere Eingabe hat diese Suche abgelöst.
        guard !Task.isCancelled else { return }

        var failed = false
        func value<T>(_ result: Result<[T], Error>) -> [T] {
            switch result {
            case .success(let list): return list
            case .failure:
                failed = true
                return []
            }
        }
        // Gesperrte Gruppen tauchen in der Suche gar nicht erst auf.
        results = Results(
            channels: value(channelResult).filter { !isLocked(.live, $0.groupName) },
            movies: value(movieResult).filter { !isLocked(.movie, $0.groupName) },
            series: value(seriesResult).filter { !isLocked(.series, $0.groupName) },
            programmes: value(programmeResult).filter { !isLocked(.live, $0.channel.groupName) }
        )
        warning = failed ? String(localized: "Einige Ergebnisse konnten nicht geladen werden.") : nil
        state = .done
    }

    private static func capture<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
