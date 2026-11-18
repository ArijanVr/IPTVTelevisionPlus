import ARJOCore
import ARJONetwork
import ARJOPlayer
import AVFoundation
import XCTest
@testable import ARJOUI

@MainActor
final class VODCatalogModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let repository = FakeVOD()
    private let store = InMemoryCredentialStore()
    private let movies = [
        VODItem(kind: .movie, sourceID: 1, name: "Heat", groupName: "Action"),
        VODItem(kind: .movie, sourceID: 2, name: "Alien", groupName: "Horror"),
    ]

    override func setUp() {
        store.saved[profile.id] = .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))
    }

    private func makeModel(provider: StubVODProvider) -> VODCatalogModel {
        VODCatalogModel(kind: .movie, profile: profile, repository: repository, credentialStore: store, makeProvider: { _ in provider })
    }

    func testLoadImportsWhenEmptyAndOnlyOnce() async {
        let model = makeModel(provider: StubVODProvider(items: [.movie: movies]))

        await model.load()
        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.groups.map(\.name), ["Action", "Horror"])
        XCTAssertEqual(repository.importCount, 1)
    }

    func testLoadUsesExistingListWithoutNetwork() async {
        repository.itemsByKind[.movie] = movies
        let model = makeModel(provider: StubVODProvider(itemsError: XtreamError.unexpectedResponse))

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(repository.importCount, 0)
    }

    func testLoadRefreshesStaleListsOnlyWhenEnabled() async {
        repository.itemsByKind[.movie] = movies
        let now = Date(timeIntervalSince1970: 1_792_859_400)
        let list = movies
        func model(_ autoRefresh: Bool) -> VODCatalogModel {
            VODCatalogModel(kind: .movie, profile: profile, repository: repository, credentialStore: store,
                            makeProvider: { _ in StubVODProvider(items: [.movie: list]) },
                            refreshesAutomatically: { autoRefresh }, clock: { now })
        }

        repository.updatedAt[.movie] = now.addingTimeInterval(-3_600)
        await model(true).load()
        XCTAssertEqual(repository.importCount, 0)

        repository.updatedAt[.movie] = now.addingTimeInterval(-30 * 3_600)
        await model(false).load()
        XCTAssertEqual(repository.importCount, 0)

        await model(true).load()
        XCTAssertEqual(repository.importCount, 1)
    }

    func testLoadFailureAndRefreshFailureMessages() async {
        let failing = makeModel(provider: StubVODProvider(itemsError: XtreamError.network(.timedOut)))
        await failing.load()
        XCTAssertEqual(failing.phase, .failed("Der Server antwortet nicht (Zeitüberschreitung)."))

        repository.itemsByKind[.movie] = movies
        let ready = makeModel(provider: StubVODProvider(itemsError: XtreamError.invalidCredentials))
        await ready.load()
        await ready.refresh()
        XCTAssertEqual(ready.phase, .ready)
        XCTAssertEqual(ready.refreshError, "Benutzername oder Passwort sind falsch.")
    }

    func testM3UProfileUsesThePlaylistProviderForMoviesAndStaysUnsupportedWithoutOne() async {
        let url = URL(string: "http://provider.example/list.m3u")!
        store.saved[profile.id] = .m3uURL(url)
        let list = movies
        let model = VODCatalogModel(kind: .movie, profile: profile, repository: repository, credentialStore: store,
                                    makeProvider: { _ in StubVODProvider(itemsError: XtreamError.unexpectedResponse) },
                                    makePlaylistProvider: { _ in StubVODProvider(items: [.movie: list]) })
        await model.load()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.groups.map(\.name), ["Action", "Horror"])

        let without = VODCatalogModel(kind: .movie, profile: profile, repository: FakeVOD(), credentialStore: store,
                                      makeProvider: { _ in StubVODProvider() })
        await without.load()
        XCTAssertEqual(without.phase, .failed("Diese Quelle enthält keine Filme und Serien."))
    }

    func testDetailsComeFromProvider() async throws {
        let provider = StubVODProvider(movie: .success(MovieDetail(plot: "Plot")), series: .success(SeriesDetail(plot: "Serie")))
        let model = makeModel(provider: provider)
        let movie = try await model.movieDetail(for: movies[0])
        let series = try await model.seriesDetail(for: VODItem(kind: .series, sourceID: 9, name: "S"))
        XCTAssertEqual(movie.plot, "Plot")
        XCTAssertEqual(series.plot, "Serie")
    }
}

@MainActor
final class VODPlayerModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let store = InMemoryCredentialStore()
    private let progress = FakeProgress()
    private let engine = FakeEngine()
    private lazy var hybrid = HybridPlaybackEngine(primary: engine, fallback: nil, player: AVPlayer())
    private let movie = PlaybackTarget(kind: .movie, streamID: 501, containerExtension: "mkv", title: "Heat")

    override func setUp() {
        store.saved[profile.id] = .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))
    }

    private func makeModel() -> VODPlayerModel {
        VODPlayerModel(profile: profile, credentialStore: store, progress: progress,
                       playback: PlaybackController(engine: hybrid, policy: ReconnectPolicy(stallTimeout: nil), sleep: { _ in }),
                       engine: hybrid)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, line: UInt = #line) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "Bedingung wurde nicht erreicht", line: line)
    }

    func testPlayBuildsMovieURLAndStartsFromBeginningWithoutProgress() async {
        let model = makeModel()
        await model.play(movie)

        XCTAssertEqual(engine.loadedURLs.map(\.absoluteString), ["http://example.com:8080/movie/anna/geheim/501.mkv"])
        XCTAssertEqual(engine.startPositions.count, 1)
        XCTAssertNil(engine.startPositions[0])
        XCTAssertTrue(model.isPresented)
        XCTAssertEqual(model.nowPlaying, movie)
    }

    func testPlayResumesFromSavedPosition() async {
        progress.stored[movie.id] = WatchProgress(target: movie, position: 1_234, duration: 6_000, watched: false)
        let model = makeModel()
        await model.play(movie)
        XCTAssertEqual(engine.startPositions, [1_234])
    }

    func testPlayDoesNotResumeWatchedOrBarelyStartedOrAlmostFinished() async {
        for saved in [
            WatchProgress(target: movie, position: 500, duration: 6_000, watched: true),
            WatchProgress(target: movie, position: 5, duration: 6_000, watched: false),
            WatchProgress(target: movie, position: 5_900, duration: 6_000, watched: false),
        ] {
            let freshEngine = FakeEngine()
            let freshHybrid = HybridPlaybackEngine(primary: freshEngine, fallback: nil, player: AVPlayer())
            progress.stored[movie.id] = saved
            let model = VODPlayerModel(profile: profile, credentialStore: store, progress: progress,
                                       playback: PlaybackController(engine: freshHybrid), engine: freshHybrid)
            await model.play(movie)
            XCTAssertNil(freshEngine.startPositions.first ?? nil, "\(saved)")
        }
    }

    func testProgressEventsAreSavedAndMarkedWatchedNearTheEnd() async {
        let model = makeModel()
        await model.play(movie)

        engine.emit(.playing)
        engine.emit(.progress(position: 600, duration: 6_000))
        await waitUntil { self.progress.saved.count == 1 }
        XCTAssertEqual(progress.saved[0].position, 600)
        XCTAssertFalse(progress.saved[0].watched)

        engine.emit(.progress(position: 5_800, duration: 6_000))
        await waitUntil { self.progress.saved.count == 2 }
        XCTAssertTrue(progress.saved[1].watched)
    }

    func testFinishedMarksWatchedAndBumpsRevision() async {
        let model = makeModel()
        await model.play(movie)
        let before = model.progressRevision

        engine.emit(.playing)
        engine.emit(.finished)

        await waitUntil { self.progress.saved.last?.watched == true }
        XCTAssertGreaterThan(model.progressRevision, before)
    }

    func testFailureAfterProgressReconnectsAtLastPosition() async {
        let model = makeModel()
        await model.play(movie)
        engine.emit(.playing)
        engine.emit(.progress(position: 321, duration: 6_000))
        await waitUntil { self.progress.saved.count == 1 }

        engine.emit(.failed("x"))

        await waitUntil { self.engine.startPositions.count == 2 }
        XCTAssertEqual(engine.startPositions, [nil, 321])
    }

    func testCloseStopsPlaybackAndBumpsRevision() async {
        let model = makeModel()
        await model.play(movie)
        let before = model.progressRevision

        model.close()

        XCTAssertFalse(model.isPresented)
        XCTAssertNil(model.nowPlaying)
        XCTAssertEqual(model.playback.status, .idle)
        XCTAssertEqual(model.progressRevision, before + 1)
    }

    func testMissingCredentialsEndsInFailedState() async {
        store.saved[profile.id] = nil
        let model = makeModel()
        await model.play(movie)
        XCTAssertEqual(model.playback.status, .failed("Die Stream-Adresse konnte nicht ermittelt werden."))
    }

    func testSetWatchedUpdatesStoreAndRevision() async {
        let model = makeModel()
        let before = model.progressRevision
        await model.setWatched(true, target: movie)
        XCTAssertEqual(progress.stored[movie.id]?.watched, true)
        XCTAssertEqual(model.progressRevision, before + 1)
    }
}

@MainActor
final class NextEpisodeTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let repository = FakeVOD()
    private let store = InMemoryCredentialStore()
    private let progress = FakeProgress()
    private let engine = FakeEngine()
    private lazy var hybrid = HybridPlaybackEngine(primary: engine, fallback: nil, player: AVPlayer())
    private let series = VODItem(kind: .series, sourceID: 42, name: "Dark", groupName: "Mystery")

    private let detail = SeriesDetail(seasons: [
        Season(number: 1, episodes: [
            Episode(id: 101, seasonNumber: 1, episodeNumber: 1, title: "Eins"),
            Episode(id: 102, seasonNumber: 1, episodeNumber: 2, title: "Zwei"),
        ]),
        Season(number: 2, episodes: [Episode(id: 201, seasonNumber: 2, episodeNumber: 1, title: "S2E1")]),
    ])

    override func setUp() {
        store.saved[profile.id] = .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))
        repository.itemsByKind[.series] = [series]
    }

    private func makeCatalog() -> VODCatalogModel {
        let detail = detail
        return VODCatalogModel(kind: .series, profile: profile, repository: repository, credentialStore: store,
                               makeProvider: { _ in StubVODProvider(series: .success(detail)) })
    }

    private func makePlayer(catalog: VODCatalogModel, autoPlay: Bool = true) -> VODPlayerModel {
        let player = VODPlayerModel(
            profile: profile, credentialStore: store, progress: progress,
            playback: PlaybackController(engine: hybrid, policy: ReconnectPolicy(stallTimeout: nil), sleep: { _ in }),
            engine: hybrid, autoPlayNextEpisode: { autoPlay }, countdown: .zero)
        player.nextEpisodeProvider = { await catalog.nextEpisode(after: $0) }
        return player
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, line: UInt = #line) async {
        for _ in 0..<5_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "Bedingung wurde nicht erreicht", line: line)
    }

    func testNextEpisodeWithinSeasonAndAcrossSeasonsAndNilAtTheEnd() async {
        let catalog = makeCatalog()
        let first = detail.seasons[0].episodes[0].target(in: series)
        let second = detail.seasons[0].episodes[1].target(in: series)
        let last = detail.seasons[1].episodes[0].target(in: series)

        let afterFirst = await catalog.nextEpisode(after: first)
        let afterSecond = await catalog.nextEpisode(after: second)
        let afterLast = await catalog.nextEpisode(after: last)
        let afterMovie = await catalog.nextEpisode(after: PlaybackTarget(kind: .movie, streamID: 1, title: "Film"))

        XCTAssertEqual(afterFirst?.streamID, 102)
        XCTAssertEqual(afterSecond?.streamID, 201)
        XCTAssertEqual(afterSecond?.subtitle, "Dark · S2 E1")
        XCTAssertNil(afterLast)
        XCTAssertNil(afterMovie)
    }

    func testFinishingAnEpisodeAnnouncesAndStartsTheNextOne() async {
        let player = makePlayer(catalog: makeCatalog())
        await player.play(detail.seasons[0].episodes[0].target(in: series))

        engine.emit(.playing)
        engine.emit(.finished)

        await waitUntil { self.engine.loadedURLs.count == 2 }
        XCTAssertEqual(engine.loadedURLs.last?.lastPathComponent, "102.mp4")
        XCTAssertEqual(player.nowPlaying?.streamID, 102)
        XCTAssertNil(player.upNext)
        XCTAssertTrue(player.isPresented)
    }

    func testLastEpisodeClosesThePlayer() async {
        let player = makePlayer(catalog: makeCatalog())
        await player.play(detail.seasons[1].episodes[0].target(in: series))

        engine.emit(.playing)
        engine.emit(.finished)

        await waitUntil { !player.isPresented }
    }

    func testMovieAndDisabledSettingCloseInsteadOfContinuing() async {
        let player = makePlayer(catalog: makeCatalog(), autoPlay: false)
        await player.play(detail.seasons[0].episodes[0].target(in: series))
        engine.emit(.playing)
        engine.emit(.finished)
        await waitUntil { !player.isPresented }
        XCTAssertEqual(engine.loadedURLs.count, 1)
    }

    func testCancellingTheAnnouncementKeepsTheNextEpisodeFromStarting() async {
        let catalog = makeCatalog()
        let player = VODPlayerModel(
            profile: profile, credentialStore: store, progress: progress,
            playback: PlaybackController(engine: hybrid, policy: ReconnectPolicy(stallTimeout: nil), sleep: { _ in }),
            engine: hybrid, autoPlayNextEpisode: { true }, countdown: .seconds(60))
        player.nextEpisodeProvider = { await catalog.nextEpisode(after: $0) }
        await player.play(detail.seasons[0].episodes[0].target(in: series))

        engine.emit(.playing)
        engine.emit(.finished)
        await waitUntil { player.upNext != nil }
        XCTAssertEqual(player.upNext?.streamID, 102)

        player.close()

        XCTAssertNil(player.upNext)
        XCTAssertEqual(engine.loadedURLs.count, 1)
    }
}

@MainActor
final class DetailModelTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let repository = FakeVOD()
    private let store = InMemoryCredentialStore()
    private let progress = FakeProgress()
    private let engine = FakeEngine()
    private lazy var hybrid = HybridPlaybackEngine(primary: engine, fallback: nil, player: AVPlayer())

    override func setUp() {
        store.saved[profile.id] = .xtream(XtreamCredentials(
            serverURL: URL(string: "http://example.com:8080")!, username: "anna", password: "geheim"))
    }

    private func makeModels(kind: VODKind, provider: StubVODProvider) -> (VODCatalogModel, VODPlayerModel) {
        (VODCatalogModel(kind: kind, profile: profile, repository: repository, credentialStore: store, makeProvider: { _ in provider }),
         VODPlayerModel(profile: profile, credentialStore: store, progress: progress,
                        playback: PlaybackController(engine: hybrid), engine: hybrid))
    }

    func testMovieDetailLoadsAndOffersResume() async {
        let item = VODItem(kind: .movie, sourceID: 501, name: "Heat", containerExtension: "mkv")
        let (catalog, player) = makeModels(kind: .movie, provider: StubVODProvider(movie: .success(MovieDetail(plot: "Plot", containerExtension: "mp4"))))
        progress.stored["movie-501"] = WatchProgress(target: item.movieTarget!, position: 700, duration: 6_000, watched: false)
        let model = MovieDetailModel(item: item, catalog: catalog, player: player)

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.detail?.plot, "Plot")
        XCTAssertEqual(model.target.containerExtension, "mp4")
        XCTAssertEqual(model.resumePosition, 700)
        XCTAssertFalse(model.isWatched)
    }

    func testMovieDetailFailureStillAllowsPlaying() async {
        let item = VODItem(kind: .movie, sourceID: 501, name: "Heat", containerExtension: "mkv")
        let (catalog, player) = makeModels(kind: .movie, provider: StubVODProvider(movie: .failure(XtreamError.network(.timedOut))))
        let model = MovieDetailModel(item: item, catalog: catalog, player: player)

        await model.load()
        await model.play()

        XCTAssertEqual(model.phase, .failed("Der Server antwortet nicht (Zeitüberschreitung)."))
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["501.mkv"])
    }

    func testMovieToggleWatchedResetsResumePosition() async {
        let item = VODItem(kind: .movie, sourceID: 501, name: "Heat")
        let (catalog, player) = makeModels(kind: .movie, provider: StubVODProvider())
        progress.stored["movie-501"] = WatchProgress(target: item.movieTarget!, position: 700, duration: 6_000, watched: false)
        let model = MovieDetailModel(item: item, catalog: catalog, player: player)
        await model.load()

        await model.toggleWatched()
        XCTAssertTrue(model.isWatched)
        XCTAssertNil(model.resumePosition)

        await model.toggleWatched()
        XCTAssertFalse(model.isWatched)
    }

    private func seriesDetail() -> SeriesDetail {
        SeriesDetail(plot: "Plot", seasons: [
            Season(number: 1, episodes: [
                Episode(id: 101, seasonNumber: 1, episodeNumber: 1, title: "Erste"),
                Episode(id: 102, seasonNumber: 1, episodeNumber: 2, title: "Zweite", containerExtension: "mkv"),
            ]),
            Season(number: 2, episodes: [Episode(id: 201, seasonNumber: 2, episodeNumber: 1, title: "S2E1")]),
        ])
    }

    func testSeriesDetailSelectsFirstSeasonAndShowsProgress() async {
        let item = VODItem(kind: .series, sourceID: 42, name: "Dark")
        let (catalog, player) = makeModels(kind: .series, provider: StubVODProvider(series: .success(seriesDetail())))
        let first = seriesDetail().seasons[0].episodes[0]
        progress.stored[first.target(in: item).id] = WatchProgress(target: first.target(in: item), position: 0, duration: 0, watched: true)
        let second = seriesDetail().seasons[0].episodes[1]
        progress.stored[second.target(in: item).id] = WatchProgress(target: second.target(in: item), position: 600, duration: 2_400, watched: false)
        let model = SeriesDetailModel(item: item, catalog: catalog, player: player)

        await model.load()

        XCTAssertEqual(model.selectedSeason, 1)
        XCTAssertEqual(model.episodes.map(\.id), [101, 102])
        XCTAssertTrue(model.isWatched(first))
        XCTAssertEqual(model.fraction(second), 0.25)

        model.selectedSeason = 2
        XCTAssertEqual(model.episodes.map(\.id), [201])
    }

    func testSeriesPlayUsesSeriesFolderAndEpisodeTarget() async {
        let item = VODItem(kind: .series, sourceID: 42, name: "Dark")
        let (catalog, player) = makeModels(kind: .series, provider: StubVODProvider(series: .success(seriesDetail())))
        let model = SeriesDetailModel(item: item, catalog: catalog, player: player)
        await model.load()

        await model.play(seriesDetail().seasons[0].episodes[1])

        XCTAssertEqual(engine.loadedURLs.map(\.absoluteString), ["http://example.com:8080/series/anna/geheim/102.mkv"])
        XCTAssertEqual(player.nowPlaying?.subtitle, "Dark · S1 E2")
        XCTAssertEqual(player.nowPlaying?.seriesID, 42)
    }

    func testSeriesToggleWatched() async {
        let item = VODItem(kind: .series, sourceID: 42, name: "Dark")
        let (catalog, player) = makeModels(kind: .series, provider: StubVODProvider(series: .success(seriesDetail())))
        let model = SeriesDetailModel(item: item, catalog: catalog, player: player)
        await model.load()
        let episode = seriesDetail().seasons[0].episodes[0]

        await model.toggleWatched(episode)
        XCTAssertTrue(model.isWatched(episode))
        await model.toggleWatched(episode)
        XCTAssertFalse(model.isWatched(episode))
    }

    func testHomeShowsContinueWatching() async {
        let target = PlaybackTarget(kind: .movie, streamID: 1, title: "Heat")
        progress.stored[target.id] = WatchProgress(target: target, position: 600, duration: 6_000, watched: false)
        let home = HomeModel(profile: profile, progress: progress)

        await home.load()

        XCTAssertEqual(home.continueWatching.map(\.id), ["movie-1"])
        XCTAssertFalse(home.loadFailed)
    }

    func testFeaturedItemsListResumeThenLastChannelThenFavorites() {
        let home = HomeModel(profile: profile, progress: progress)
        let resume = WatchProgress(target: PlaybackTarget(kind: .movie, streamID: 1, title: "Heat"), position: 600, duration: 6_000, watched: false)
        let last = Channel(id: "1", name: "Eins", source: .xtream(streamID: 1))
        let favorite = Channel(id: "2", name: "Zwei", source: .xtream(streamID: 2))

        XCTAssertEqual(home.featuredItems(resumable: [resume], lastChannel: last, favorites: [last, favorite]),
                       [.resume(resume), .channel(last), .channel(favorite)])
        XCTAssertEqual(home.featuredItems(resumable: [], lastChannel: nil, favorites: [favorite]), [.channel(favorite)])
        XCTAssertEqual(home.featuredItems(resumable: [], lastChannel: last, favorites: [favorite], limit: 1), [.channel(last)])
        XCTAssertTrue(home.featuredItems(resumable: [], lastChannel: nil, favorites: []).isEmpty)
    }

    func testHomeLoadsRecentMoviesAndSeriesSeparately() async {
        let vod = FakeVOD()
        let date = Date(timeIntervalSince1970: 100)
        vod.itemsByKind = [
            .movie: [VODItem(kind: .movie, sourceID: 1, name: "Film", addedAt: date)],
            .series: [VODItem(kind: .series, sourceID: 2, name: "Serie", addedAt: date)],
        ]
        let home = HomeModel(profile: profile, progress: progress, vod: vod)

        await home.load()

        XCTAssertEqual(home.recentMovies.map(\.name), ["Film"])
        XCTAssertEqual(home.recentSeries.map(\.name), ["Serie"])
    }
}

private final class RecordingTopShelf: TopShelfPublishing, @unchecked Sendable {
    var snapshots: [TopShelfSnapshot] = []
    func publish(_ snapshot: TopShelfSnapshot) { snapshots.append(snapshot) }
}

@MainActor
final class TopShelfTests: XCTestCase {
    private let profile = Profile(name: "example.com", kind: .xtream)
    private let progress = FakeProgress()
    private let shelf = RecordingTopShelf()

    private func target(_ id: Int, group: String? = nil) -> PlaybackTarget {
        PlaybackTarget(kind: .movie, streamID: id, title: "Film \(id)", posterURL: URL(string: "http://img.example/\(id).jpg"), groupName: group)
    }

    func testPublishesContinueWatchingWithDeepLinksAndRespectsLimitAndLockedGroups() async {
        for id in 1...12 {
            progress.stored["movie-\(id)"] = WatchProgress(
                target: target(id, group: id == 3 ? "FSK 18" : nil), position: 600, duration: 6_000, watched: false,
                updatedAt: Date(timeIntervalSince1970: Double(id)))
        }
        let home = HomeModel(profile: profile, progress: progress, topShelf: shelf, isEnabled: { true },
                             isPublishable: { $0.target.groupName != "FSK 18" })

        await home.load()

        let snapshot = try! XCTUnwrap(shelf.snapshots.last)
        XCTAssertEqual(snapshot.items.count, 10)
        XCTAssertFalse(snapshot.items.contains { $0.id == "movie-3" })
        XCTAssertEqual(snapshot.items.first?.id, "movie-12", "neueste zuerst")
        XCTAssertEqual(DeepLink.playItemID(from: snapshot.items[0].deepLink), "movie-12")
        XCTAssertEqual(snapshot.items[0].progress, 0.1, accuracy: 0.001)
    }

    func testDisabledTopShelfPublishesAnEmptyList() async {
        progress.stored["movie-1"] = WatchProgress(target: target(1), position: 600, duration: 6_000, watched: false)
        let home = HomeModel(profile: profile, progress: progress, topShelf: shelf, isEnabled: { false })
        await home.load()
        XCTAssertEqual(shelf.snapshots.last?.items, [])
    }

    func testDeepLinkParsing() {
        XCTAssertEqual(DeepLink.playItemID(from: URL(string: "arjotv://play?item=episode-77")!), "episode-77")
        XCTAssertNil(DeepLink.playItemID(from: URL(string: "arjotv://play")!))
        XCTAssertNil(DeepLink.playItemID(from: URL(string: "https://play?item=movie-1")!))
        XCTAssertNil(DeepLink.playItemID(from: URL(string: "arjotv://other?item=movie-1")!))
    }

    func testAppModelKeepsOpenedURLUntilConsumed() {
        let model = AppModel(profiles: FakeProfiles(), activeProfile: FakeActiveProfile(), credentialStore: InMemoryCredentialStore(), cleanups: [])
        let url = DeepLink.play(itemID: "movie-1")
        model.open(url)
        XCTAssertEqual(model.pendingDeepLink, url)
        model.consumeDeepLink()
        XCTAssertNil(model.pendingDeepLink)
    }
}
