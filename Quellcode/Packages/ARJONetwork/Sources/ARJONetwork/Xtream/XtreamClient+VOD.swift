import ARJOCore
import Foundation

extension XtreamClient: VODProviding {
    public func vodItems(kind: VODKind) async throws -> [VODItem] {
        switch kind {
        case .movie: try await movies()
        case .series: try await series()
        }
    }

    public func movieDetail(for item: VODItem) async throws -> MovieDetail {
        let data = try await perform(action: "get_vod_info", parameters: ["vod_id": String(item.sourceID)])
        guard let response = try? Self.decoder.decode(XtreamVODInfoDTO.self, from: data) else {
            throw XtreamError.unexpectedResponse
        }
        let info = response.info
        return MovieDetail(
            plot: Self.nonEmpty(info?.plot),
            genre: Self.nonEmpty(info?.genre),
            cast: Self.nonEmpty(info?.cast),
            director: Self.nonEmpty(info?.director),
            durationSeconds: info?.durationSecs.flatMap { Int($0.value) },
            rating: Self.rating(info?.rating),
            releaseDate: Self.nonEmpty(info?.releasedate?.value),
            backdropURL: info?.backdropPath?.values.first.flatMap { URL(string: $0) },
            containerExtension: Self.nonEmpty(response.movieData?.containerExtension)
        )
    }

    public func seriesDetail(for item: VODItem) async throws -> SeriesDetail {
        let data = try await perform(action: "get_series_info", parameters: ["series_id": String(item.sourceID)])
        guard let response = try? Self.decoder.decode(XtreamSeriesInfoDTO.self, from: data) else {
            throw XtreamError.unexpectedResponse
        }

        var bySeason: [Int: [Episode]] = [:]
        for (fallbackSeason, dto) in response.episodes {
            guard let id = Int(dto.id.value) else { continue }
            let season = dto.season.flatMap { Int($0.value) } ?? fallbackSeason ?? 1
            let number = dto.episodeNum.flatMap { Int($0.value) } ?? 0
            bySeason[season, default: []].append(Episode(
                id: id,
                seasonNumber: season,
                episodeNumber: number,
                title: Self.nonEmpty(dto.title) ?? "Episode \(number)",
                plot: Self.nonEmpty(dto.info?.plot),
                durationSeconds: dto.info?.durationSecs.flatMap { Int($0.value) },
                imageURL: Self.nonEmpty(dto.info?.movieImage).flatMap { URL(string: $0) },
                containerExtension: Self.nonEmpty(dto.containerExtension) ?? PlaybackTarget.defaultExtension
            ))
        }
        let seasons = bySeason.keys.sorted().map { number in
            Season(number: number, episodes: bySeason[number, default: []].sorted {
                ($0.episodeNumber, $0.id) < ($1.episodeNumber, $1.id)
            })
        }

        let info = response.info
        return SeriesDetail(
            plot: Self.nonEmpty(info?.plot),
            genre: Self.nonEmpty(info?.genre),
            cast: Self.nonEmpty(info?.cast),
            director: Self.nonEmpty(info?.director),
            rating: Self.rating(info?.rating),
            releaseDate: Self.nonEmpty(info?.releaseDate?.value),
            backdropURL: info?.backdropPath?.values.first.flatMap { URL(string: $0) },
            seasons: seasons
        )
    }

    private func movies() async throws -> [VODItem] {
        let groupNames = try await categoryNames(action: "get_vod_categories")
        let data = try await perform(action: "get_vod_streams")
        guard let streams = try? Self.decoder.decode([XtreamVODStreamDTO].self, from: data) else {
            throw XtreamError.unexpectedResponse
        }
        return streams.compactMap { stream in
            guard let id = Int(stream.streamId.value) else { return nil }
            return VODItem(
                kind: .movie,
                sourceID: id,
                name: Self.nonEmpty(stream.name) ?? "Film \(id)",
                posterURL: Self.nonEmpty(stream.streamIcon).flatMap { URL(string: $0) },
                groupName: stream.categoryId.flatMap { groupNames[$0.value] } ?? Channel.ungroupedName,
                rating: Self.rating(stream.rating),
                year: Self.nonEmpty(stream.year?.value),
                containerExtension: Self.nonEmpty(stream.containerExtension),
                addedAt: stream.added.flatMap { TimeInterval($0.value) }.map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    private func series() async throws -> [VODItem] {
        let groupNames = try await categoryNames(action: "get_series_categories")
        let data = try await perform(action: "get_series")
        guard let list = try? Self.decoder.decode([XtreamSeriesDTO].self, from: data) else {
            throw XtreamError.unexpectedResponse
        }
        return list.compactMap { series in
            guard let id = Int(series.seriesId.value) else { return nil }
            return VODItem(
                kind: .series,
                sourceID: id,
                name: Self.nonEmpty(series.name) ?? "Serie \(id)",
                posterURL: Self.nonEmpty(series.cover).flatMap { URL(string: $0) },
                groupName: series.categoryId.flatMap { groupNames[$0.value] } ?? Channel.ungroupedName,
                rating: Self.rating(series.rating),
                year: series.releaseDate.map { String($0.value.prefix(4)) }.flatMap { Int($0) == nil ? nil : $0 }
            )
        }
    }

    private func categoryNames(action: String) async throws -> [String: String] {
        let data = try await perform(action: action)
        guard let categories = try? Self.decoder.decode([XtreamCategoryDTO].self, from: data) else {
            throw XtreamError.unexpectedResponse
        }
        return Dictionary(
            categories.compactMap { category in category.categoryName.map { (category.categoryId.value, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Xtream liefert `0` oder leer, wenn es keine Bewertung gibt.
    private static func rating(_ value: LossyString?) -> Double? {
        value.flatMap { Double($0.value) }.flatMap { $0 > 0 ? $0 : nil }
    }
}
