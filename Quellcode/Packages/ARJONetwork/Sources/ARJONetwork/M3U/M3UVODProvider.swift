import ARJOCore
import Foundation

/// Filme und Serien aus einer M3U-Playlist. Die Playlist enthält keine Handlung oder Besetzung;
/// Staffeln und Episoden werden aus den Namen (`S01E02`) abgeleitet.
public struct M3UVODProvider: VODProviding {
    private let url: URL
    private let index: M3UVODIndex

    public init(url: URL, download: @escaping @Sendable (URLRequest) async throws -> URL = { try await FileDownloader.download($0) }) {
        self.url = url
        index = M3UVODIndex.shared(for: url, download: download)
    }

    public func vodItems(kind: VODKind) async throws -> [VODItem] {
        let content = try await index.content()
        return kind == .movie ? content.movies : content.series
    }

    public func movieDetail(for item: VODItem) async throws -> MovieDetail {
        MovieDetail(containerExtension: item.containerExtension)
    }

    public func seriesDetail(for item: VODItem) async throws -> SeriesDetail {
        SeriesDetail(seasons: item.seasons ?? [])
    }
}

/// Liest die Playlist einmal für Filme und Serien (beide Listen werden hintereinander geladen).
actor M3UVODIndex {
    struct Content: Sendable {
        var movies: [VODItem]
        var series: [VODItem]
    }

    private static let maxAge: TimeInterval = 120
    private static var shared: [URL: M3UVODIndex] = [:]
    private static let lock = NSLock()

    private let url: URL
    private let download: @Sendable (URLRequest) async throws -> URL
    private var cached: (date: Date, content: Content)?

    private init(url: URL, download: @escaping @Sendable (URLRequest) async throws -> URL) {
        self.url = url
        self.download = download
    }

    static func shared(for url: URL, download: @escaping @Sendable (URLRequest) async throws -> URL) -> M3UVODIndex {
        lock.withLock {
            if let existing = shared[url] { return existing }
            let created = M3UVODIndex(url: url, download: download)
            shared[url] = created
            return created
        }
    }

    func content() async throws -> Content {
        if let cached, Date().timeIntervalSince(cached.date) < Self.maxAge { return cached.content }
        let content = try await load()
        cached = (Date(), content)
        return content
    }

    private func load() async throws -> Content {
        let isTemporary = !url.isFileURL
        let file = isTemporary ? try await download(URLRequest(url: url)) : url
        defer { if isTemporary { try? FileManager.default.removeItem(at: file) } }

        var movies: [VODItem] = []
        var shows: [String: Show] = [:]
        var showOrder: [String] = []

        _ = try await M3UStreamParser().parse(fileURL: file) { entry in
            switch M3UMediaClassifier.classify(entry) {
            case .live:
                break
            case .movie:
                movies.append(Self.movie(from: entry))
            case .episode(let show, let season, let number, let title):
                let key = show.lowercased()
                if shows[key] == nil {
                    shows[key] = Show(name: show, group: entry.groupTitle ?? Channel.ungroupedName, poster: entry.logoURL)
                    showOrder.append(key)
                }
                shows[key]?.episodes.append(Episode(
                    id: ContentIdentity.mediaID(for: entry.url),
                    seasonNumber: season,
                    episodeNumber: number,
                    title: title ?? "Episode \(number)",
                    imageURL: entry.logoURL,
                    containerExtension: Self.fileExtension(of: entry.url),
                    streamURL: entry.url
                ))
            }
        }

        let series = showOrder.compactMap { shows[$0] }.map { show in
            VODItem(
                kind: .series,
                sourceID: ContentIdentity.stableHash("series:" + show.name.lowercased()),
                name: show.name,
                posterURL: show.poster,
                groupName: show.group,
                seasons: Dictionary(grouping: show.episodes, by: \.seasonNumber).keys.sorted().map { number in
                    Season(number: number, episodes: show.episodes.filter { $0.seasonNumber == number }
                        .sorted { ($0.episodeNumber, $0.id) < ($1.episodeNumber, $1.id) })
                }
            )
        }
        return Content(movies: movies, series: series)
    }

    private struct Show {
        var name: String
        var group: String
        var poster: URL?
        var episodes: [Episode] = []
    }

    private static func movie(from entry: PlaylistEntry) -> VODItem {
        VODItem(
            kind: .movie,
            sourceID: ContentIdentity.mediaID(for: entry.url),
            name: entry.name,
            posterURL: entry.logoURL,
            groupName: entry.groupTitle ?? Channel.ungroupedName,
            year: year(in: entry.name),
            containerExtension: fileExtension(of: entry.url),
            streamURL: entry.url
        )
    }

    private static func fileExtension(of url: URL) -> String {
        url.pathExtension.isEmpty ? PlaybackTarget.defaultExtension : url.pathExtension.lowercased()
    }

    private static func year(in name: String) -> String? {
        guard let range = name.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) else { return nil }
        return String(name[range])
    }
}
