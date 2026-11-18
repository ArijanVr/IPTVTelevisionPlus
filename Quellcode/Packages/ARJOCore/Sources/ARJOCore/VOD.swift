import Foundation

public enum VODKind: String, Sendable, Codable, CaseIterable {
    case movie
    case series
}

/// Eintrag in der Film- oder Serienliste. Details (Handlung, Besetzung, Episoden) werden bei Bedarf geladen.
public struct VODItem: Sendable, Hashable, Codable, Identifiable {
    public var kind: VODKind
    public var sourceID: Int
    public var name: String
    public var posterURL: URL?
    public var groupName: String
    public var rating: Double?
    public var year: String?
    /// Nur bei Filmen: Containerformat aus der Liste (`mp4`, `mkv` …).
    public var containerExtension: String?
    public var addedAt: Date?
    /// Direkte Stream-Adresse (Film aus einer M3U-Playlist); bei Xtream wird sie aus den Zugangsdaten gebaut.
    public var streamURL: URL?
    /// Mitgelieferte Staffeln (Serie aus einer M3U-Playlist); bei Xtream werden sie bei Bedarf geladen.
    public var seasons: [Season]?

    public var id: String { "\(kind.rawValue)-\(sourceID)" }

    public init(
        kind: VODKind,
        sourceID: Int,
        name: String,
        posterURL: URL? = nil,
        groupName: String = Channel.ungroupedName,
        rating: Double? = nil,
        year: String? = nil,
        containerExtension: String? = nil,
        addedAt: Date? = nil,
        streamURL: URL? = nil,
        seasons: [Season]? = nil
    ) {
        self.kind = kind
        self.sourceID = sourceID
        self.name = name
        self.posterURL = posterURL
        self.groupName = groupName
        self.rating = rating
        self.year = year
        self.containerExtension = containerExtension
        self.addedAt = addedAt
        self.streamURL = streamURL
        self.seasons = seasons
    }

    public var movieTarget: PlaybackTarget? {
        guard kind == .movie else { return nil }
        return PlaybackTarget(
            kind: .movie, streamID: sourceID, containerExtension: containerExtension ?? PlaybackTarget.defaultExtension,
            title: name, posterURL: posterURL, groupName: groupName, directURL: streamURL
        )
    }
}

public struct MovieDetail: Sendable, Hashable {
    public var plot: String?
    public var genre: String?
    public var cast: String?
    public var director: String?
    public var durationSeconds: Int?
    public var rating: Double?
    public var releaseDate: String?
    public var backdropURL: URL?
    public var containerExtension: String?

    public init(
        plot: String? = nil, genre: String? = nil, cast: String? = nil, director: String? = nil,
        durationSeconds: Int? = nil, rating: Double? = nil, releaseDate: String? = nil,
        backdropURL: URL? = nil, containerExtension: String? = nil
    ) {
        self.plot = plot
        self.genre = genre
        self.cast = cast
        self.director = director
        self.durationSeconds = durationSeconds
        self.rating = rating
        self.releaseDate = releaseDate
        self.backdropURL = backdropURL
        self.containerExtension = containerExtension
    }
}

public struct Episode: Sendable, Hashable, Codable, Identifiable {
    /// Stream-ID der Episode (nicht die der Serie).
    public var id: Int
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var title: String
    public var plot: String?
    public var durationSeconds: Int?
    public var imageURL: URL?
    public var containerExtension: String
    /// Direkte Stream-Adresse (Episode aus einer M3U-Playlist).
    public var streamURL: URL?

    public init(
        id: Int, seasonNumber: Int, episodeNumber: Int, title: String, plot: String? = nil,
        durationSeconds: Int? = nil, imageURL: URL? = nil, containerExtension: String = PlaybackTarget.defaultExtension,
        streamURL: URL? = nil
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.plot = plot
        self.durationSeconds = durationSeconds
        self.imageURL = imageURL
        self.containerExtension = containerExtension
        self.streamURL = streamURL
    }

    public func target(in series: VODItem) -> PlaybackTarget {
        PlaybackTarget(
            kind: .episode, streamID: id, containerExtension: containerExtension,
            title: title, subtitle: "\(series.name) · S\(seasonNumber) E\(episodeNumber)",
            posterURL: imageURL ?? series.posterURL, seriesID: series.sourceID, groupName: series.groupName,
            seriesName: series.name, directURL: streamURL, seasonNumber: seasonNumber, episodeNumber: episodeNumber
        )
    }
}

public struct Season: Sendable, Hashable, Codable, Identifiable {
    public var number: Int
    public var episodes: [Episode]
    public var id: Int { number }

    public init(number: Int, episodes: [Episode]) {
        self.number = number
        self.episodes = episodes
    }
}

public struct SeriesDetail: Sendable, Hashable {
    public var plot: String?
    public var genre: String?
    public var cast: String?
    public var director: String?
    public var rating: Double?
    public var releaseDate: String?
    public var backdropURL: URL?
    public var seasons: [Season]

    public init(
        plot: String? = nil, genre: String? = nil, cast: String? = nil, director: String? = nil,
        rating: Double? = nil, releaseDate: String? = nil, backdropURL: URL? = nil, seasons: [Season] = []
    ) {
        self.plot = plot
        self.genre = genre
        self.cast = cast
        self.director = director
        self.rating = rating
        self.releaseDate = releaseDate
        self.backdropURL = backdropURL
        self.seasons = seasons
    }
}

/// Alles, was zum Abspielen und späteren Wiederfinden («Weiterschauen») eines Films oder einer Episode nötig ist.
public struct PlaybackTarget: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case movie
        case episode
    }

    public static let defaultExtension = "mp4"

    public var kind: Kind
    public var streamID: Int
    public var containerExtension: String
    public var title: String
    public var subtitle: String?
    public var posterURL: URL?
    public var seriesID: Int?
    /// Kategorie des Films bzw. der Serie; nötig, damit die Kindersicherung auch «Weiterschauen» abdeckt.
    public var groupName: String?
    /// Name der Serie; nötig, um nach einer Episode die nächste zu finden.
    public var seriesName: String?
    /// Direkte Stream-Adresse statt Xtream-Adresse (Inhalte aus einer M3U-Playlist). Kann Zugangsdaten enthalten
    /// und wird deshalb nicht im Wiedergabestand gespeichert, sondern beim Abspielen aus dem Katalog ermittelt.
    public var directURL: URL?
    /// Staffel und Folge (nur Episoden).
    public var seasonNumber: Int?
    public var episodeNumber: Int?

    public var id: String { "\(kind.rawValue)-\(streamID)" }

    public init(
        kind: Kind, streamID: Int, containerExtension: String = PlaybackTarget.defaultExtension,
        title: String, subtitle: String? = nil, posterURL: URL? = nil, seriesID: Int? = nil, groupName: String? = nil,
        seriesName: String? = nil, directURL: URL? = nil, seasonNumber: Int? = nil, episodeNumber: Int? = nil
    ) {
        self.kind = kind
        self.streamID = streamID
        self.containerExtension = containerExtension
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.seriesID = seriesID
        self.groupName = groupName
        self.seriesName = seriesName
        self.directURL = directURL
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}

public struct WatchProgress: Sendable, Hashable, Codable, Identifiable {
    public var target: PlaybackTarget
    public var position: TimeInterval
    public var duration: TimeInterval
    public var watched: Bool
    public var updatedAt: Date

    public var id: String { target.id }

    public init(target: PlaybackTarget, position: TimeInterval, duration: TimeInterval, watched: Bool, updatedAt: Date = Date()) {
        self.target = target
        self.position = position
        self.duration = duration
        self.watched = watched
        self.updatedAt = updatedAt
    }

    /// Anteil 0 bis 1; 1 bei als gesehen markierten Einträgen.
    public var fraction: Double {
        if watched { return 1 }
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
