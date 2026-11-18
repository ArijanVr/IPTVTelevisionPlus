import ARJOCore
import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class HomeModel {
    /// Was die Startseite gross zeigt (Hero): zuerst, was man gerade schaut, sonst der letzte Sender.
    public enum Featured: Equatable {
        case resume(WatchProgress)
        case channel(Channel)
    }

    public private(set) var continueWatching: [WatchProgress] = []
    public private(set) var recentMovies: [VODItem] = []
    public private(set) var recentSeries: [VODItem] = []
    public private(set) var loadFailed = false

    private static let topShelfLimit = 10
    private static let recentLimit = 20
    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "home")

    private let profile: Profile
    private let progress: any ProgressRepository
    private let topShelf: (any TopShelfPublishing)?
    private let isEnabled: @MainActor () -> Bool
    private let isPublishable: @MainActor (WatchProgress) -> Bool
    private let vod: (any VODRepository)?

    /// - Parameters:
    ///   - vod: Quelle für «Neu hinzugefügt» bei Filmen und Serien.
    ///   - topShelf: Empfänger für den Top-Shelf-Stand (nur Apple TV).
    ///   - isPublishable: Schliesst Einträge aus, die nicht im Top Shelf erscheinen dürfen (Kindersicherung).
    public init(
        profile: Profile,
        progress: any ProgressRepository,
        topShelf: (any TopShelfPublishing)? = nil,
        isEnabled: @escaping @MainActor () -> Bool = { true },
        isPublishable: @escaping @MainActor (WatchProgress) -> Bool = { _ in true },
        vod: (any VODRepository)? = nil
    ) {
        self.vod = vod
        self.profile = profile
        self.progress = progress
        self.topShelf = topShelf
        self.isEnabled = isEnabled
        self.isPublishable = isPublishable
    }

    public func load() async {
        do {
            continueWatching = try await progress.continueWatching(for: profile.id, limit: 20)
            loadFailed = false
        } catch {
            loadFailed = true
            return
        }
        publishTopShelf()
        await loadRecents()
    }

    /// Wählt die grossen Bilder der Startseite aus bereits gefilterten Angeboten (ohne gesperrte oder ausgeblendete):
    /// angefangene Filme zuerst, dann der letzte Sender, dann Favoriten.
    public func featuredItems(resumable: [WatchProgress], lastChannel: Channel?, favorites: [Channel], limit: Int = 5) -> [Featured] {
        var items = resumable.prefix(3).map(Featured.resume)
        if let lastChannel { items.append(.channel(lastChannel)) }
        items += favorites.filter { $0 != lastChannel }.map(Featured.channel)
        return Array(items.prefix(limit))
    }

    private func loadRecents() async {
        guard let vod else { return }
        do {
            recentMovies = try await vod.recentItems(for: profile.id, kind: .movie, limit: Self.recentLimit)
            recentSeries = try await vod.recentItems(for: profile.id, kind: .series, limit: Self.recentLimit)
        } catch {
            // «Neu hinzugefügt» ist ein Zusatz: bei einem Lesefehler bleiben die Reihen einfach aus.
            Self.log.error("Neuheiten nicht gelesen: \(error.localizedDescription)")
        }
    }

    private func publishTopShelf() {
        guard let topShelf else { return }
        let items = isEnabled()
            ? continueWatching.filter(isPublishable).prefix(Self.topShelfLimit).map {
                TopShelfItem(
                    id: $0.id, title: $0.target.title, subtitle: $0.target.subtitle, imageURL: $0.target.posterURL,
                    progress: $0.fraction, deepLink: DeepLink.play(itemID: $0.id)
                )
            }
            : []
        topShelf.publish(TopShelfSnapshot(items: Array(items)))
    }
}

@MainActor
@Observable
public final class MovieDetailModel {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    public let item: VODItem
    public private(set) var phase: Phase = .loading
    public private(set) var detail: MovieDetail?
    public private(set) var progress: WatchProgress?

    private let catalog: VODCatalogModel
    private let player: VODPlayerModel

    public init(item: VODItem, catalog: VODCatalogModel, player: VODPlayerModel) {
        self.item = item
        self.catalog = catalog
        self.player = player
    }

    /// Das Containerformat aus den Details hat Vorrang vor dem aus der Liste.
    public var target: PlaybackTarget {
        var target = item.movieTarget ?? PlaybackTarget(kind: .movie, streamID: item.sourceID, title: item.name)
        if let ext = detail?.containerExtension { target.containerExtension = ext }
        return target
    }

    public var isWatched: Bool { progress?.watched ?? false }

    /// Position, ab der «Fortsetzen» startet; `nil` bei neuem oder bereits gesehenem Film.
    public var resumePosition: TimeInterval? {
        guard let progress, !progress.watched, progress.position > VODPlayerModel.minimumResumePosition else { return nil }
        return progress.position
    }

    public func load() async {
        do {
            detail = try await catalog.movieDetail(for: item)
            phase = .ready
        } catch {
            phase = .failed(VODCatalogModel.message(for: error))
        }
        await reloadProgress()
    }

    public func reloadProgress() async {
        progress = await player.progress(for: [target])[target.id]
    }

    public func play() async {
        await player.play(target)
    }

    public func toggleWatched() async {
        await player.setWatched(!isWatched, target: target)
        await reloadProgress()
    }
}

@MainActor
@Observable
public final class SeriesDetailModel {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    public let item: VODItem
    public private(set) var phase: Phase = .loading
    public private(set) var detail: SeriesDetail?
    public var selectedSeason: Int?
    public private(set) var progress: [String: WatchProgress] = [:]

    private let catalog: VODCatalogModel
    private let player: VODPlayerModel

    public init(item: VODItem, catalog: VODCatalogModel, player: VODPlayerModel) {
        self.item = item
        self.catalog = catalog
        self.player = player
    }

    public var seasons: [Season] { detail?.seasons ?? [] }

    public var episodes: [Episode] {
        seasons.first { $0.number == selectedSeason }?.episodes ?? []
    }

    public func load() async {
        do {
            let loaded = try await catalog.seriesDetail(for: item)
            detail = loaded
            selectedSeason = selectedSeason ?? loaded.seasons.first?.number
            phase = .ready
        } catch {
            phase = .failed(VODCatalogModel.message(for: error))
        }
        await reloadProgress()
    }

    public func reloadProgress() async {
        let targets = seasons.flatMap(\.episodes).map { $0.target(in: item) }
        progress = targets.isEmpty ? [:] : await player.progress(for: targets)
    }

    public func isWatched(_ episode: Episode) -> Bool {
        progress[episode.target(in: item).id]?.watched ?? false
    }

    /// Anteil 0 bis 1 für den Fortschrittsbalken; 0 bei unberührten Episoden.
    public func fraction(_ episode: Episode) -> Double {
        progress[episode.target(in: item).id]?.fraction ?? 0
    }

    public func play(_ episode: Episode) async {
        await player.play(episode.target(in: item))
    }

    public func toggleWatched(_ episode: Episode) async {
        await player.setWatched(!isWatched(episode), target: episode.target(in: item))
        await reloadProgress()
    }
}
