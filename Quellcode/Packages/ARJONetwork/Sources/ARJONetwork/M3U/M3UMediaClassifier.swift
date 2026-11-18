import ARJOCore
import Foundation

/// Erkennt in einer M3U-Playlist, ob ein Eintrag ein Live-Sender, ein Film oder eine Serien-Episode ist.
/// Playlists haben dafür kein Feld; die Erkennung nutzt typische Merkmale: Xtream-Pfade (`/movie/`, `/series/`),
/// Dateiendungen von Aufnahmen (`.mkv`, `.mp4` …) und Namen mit `S01E02`.
public enum M3UMediaClassifier {
    public enum Kind: Equatable, Sendable {
        case live
        case movie
        case episode(show: String, season: Int, number: Int, title: String?)
    }

    private static let recordingExtensions: Set<String> = ["mkv", "mp4", "avi", "mov", "m4v", "wmv", "flv", "webm"]

    // «Show S01E02 – Titel», «Show s1 e2», «Show 1x02»
    private static let episodePattern = try! NSRegularExpression(
        pattern: #"^(.*?)[\s._\-:]*(?:[Ss](\d{1,2})[\s._\-]*[Ee](\d{1,3})|(\d{1,2})[xX](\d{1,3}))(?:[\s._\-:]+(.*))?$"#
    )

    public static func classify(_ entry: PlaylistEntry) -> Kind {
        let path = entry.url.path.lowercased()
        let isSeriesPath = path.contains("/series/")
        let isMoviePath = path.contains("/movie/")
        let isRecording = recordingExtensions.contains(entry.url.pathExtension.lowercased())

        guard isSeriesPath || isMoviePath || isRecording else { return .live }
        if let episode = parseEpisode(entry.name) { return episode }
        return isSeriesPath ? .live : .movie
    }

    static func parseEpisode(_ name: String) -> Kind? {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = episodePattern.firstMatch(in: name, range: range) else { return nil }

        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: name).map { String(name[$0]) }
        }
        let show = group(1)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !show.isEmpty,
              let season = Int(group(2) ?? group(4) ?? ""), let number = Int(group(3) ?? group(5) ?? "")
        else { return nil }
        let title = group(6)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .episode(show: show, season: season, number: number, title: title?.isEmpty == true ? nil : title)
    }
}
