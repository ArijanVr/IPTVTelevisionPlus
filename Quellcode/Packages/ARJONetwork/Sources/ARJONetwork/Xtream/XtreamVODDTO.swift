import Foundation

/// Xtream liefert Felder mal als Text, mal als Liste.
struct LossyStrings: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            values = list
        } else if let single = try? container.decode(String.self) {
            values = single.isEmpty ? [] : [single]
        } else {
            values = []
        }
    }
}

/// Alle DTOs werden mit `.convertFromSnakeCase` dekodiert.
struct XtreamVODStreamDTO: Decodable {
    var streamId: LossyString
    var name: String?
    var streamIcon: String?
    var rating: LossyString?
    var added: LossyString?
    var categoryId: LossyString?
    var containerExtension: String?
    var year: LossyString?
}

struct XtreamSeriesDTO: Decodable {
    var seriesId: LossyString
    var name: String?
    var cover: String?
    var rating: LossyString?
    var releaseDate: LossyString?
    var categoryId: LossyString?
}

struct XtreamVODInfoDTO: Decodable {
    struct Info: Decodable {
        var plot: String?
        var genre: String?
        var cast: String?
        var director: String?
        var rating: LossyString?
        var releasedate: LossyString?
        var durationSecs: LossyString?
        var backdropPath: LossyStrings?
    }

    struct MovieData: Decodable {
        var containerExtension: String?
    }

    var info: Info?
    var movieData: MovieData?

    private enum CodingKeys: String, CodingKey { case info, movieData }

    /// Ohne Infos liefern manche Server `"info": []` statt eines Objekts.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        info = try? container.decode(Info.self, forKey: .info)
        movieData = try? container.decode(MovieData.self, forKey: .movieData)
    }
}

struct XtreamEpisodeDTO: Decodable {
    struct Info: Decodable {
        var plot: String?
        var movieImage: String?
        var durationSecs: LossyString?
    }

    var id: LossyString
    var episodeNum: LossyString?
    var title: String?
    var containerExtension: String?
    var season: LossyString?
    var info: Info?

    private enum CodingKeys: String, CodingKey { case id, episodeNum, title, containerExtension, season, info }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(LossyString.self, forKey: .id)
        episodeNum = try? container.decode(LossyString.self, forKey: .episodeNum)
        title = try? container.decode(String.self, forKey: .title)
        containerExtension = try? container.decode(String.self, forKey: .containerExtension)
        season = try? container.decode(LossyString.self, forKey: .season)
        info = try? container.decode(Info.self, forKey: .info)
    }
}

struct XtreamSeriesInfoDTO: Decodable {
    struct Info: Decodable {
        var plot: String?
        var genre: String?
        var cast: String?
        var director: String?
        var rating: LossyString?
        var releaseDate: LossyString?
        var backdropPath: LossyStrings?
    }

    var info: Info?
    /// Staffelnummer aus dem Schlüssel (falls vorhanden) und die Episode.
    var episodes: [(fallbackSeason: Int?, episode: XtreamEpisodeDTO)]

    private enum CodingKeys: String, CodingKey { case info, episodes }

    /// `episodes` ist je nach Server ein Objekt nach Staffelnummer oder eine verschachtelte Liste.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        info = try? container.decode(Info.self, forKey: .info)

        if let bySeason = try? container.decode([String: [XtreamEpisodeDTO]].self, forKey: .episodes) {
            episodes = bySeason.flatMap { key, list in list.map { (Int(key), $0) } }
        } else if let nested = try? container.decode([[XtreamEpisodeDTO]].self, forKey: .episodes) {
            episodes = nested.flatMap { $0.map { (nil, $0) } }
        } else {
            episodes = []
        }
    }
}
