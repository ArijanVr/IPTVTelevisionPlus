import ARJOCore
import Foundation

public enum StreamURLError: Error, Equatable {
    /// Der Sender gehört zu einer anderen Quelle als die übergebenen Zugangsdaten.
    case credentialsDoNotMatchChannel
}

public enum StreamURLResolver {
    /// Film (`/movie/`) oder Episode (`/series/`) im Containerformat des Anbieters.
    public static func mediaURL(for target: PlaybackTarget, credentials: SourceCredentials) throws -> URL {
        if let direct = target.directURL { return direct }
        guard case .xtream(let xtream) = credentials else { throw StreamURLError.credentialsDoNotMatchChannel }
        guard var components = URLComponents(url: xtream.serverURL, resolvingAgainstBaseURL: false) else {
            throw XtreamError.invalidServerURL
        }
        let folder = target.kind == .movie ? "movie" : "series"
        components.percentEncodedPath = "/\(folder)/\(PercentEncoding.encode(xtream.username))"
            + "/\(PercentEncoding.encode(xtream.password))/\(target.streamID).\(PercentEncoding.encode(target.containerExtension))"
        guard let url = components.url else { throw XtreamError.invalidServerURL }
        return url
    }

    /// HLS (`.m3u8`) für AVPlayer, der rohes MPEG-TS nicht abspielt. Mit `transportStream` direkt `.ts` für die
    /// Fallback-Engine: das startet schneller und ruckelt bei vielen Anbietern weniger als deren HLS-Umsetzung.
    public static func liveURL(for channel: Channel, credentials: SourceCredentials, transportStream: Bool = false) throws -> URL {
        switch (channel.source, credentials) {
        case (.url(let url), _):
            return url
        case (.xtream(let streamID), .xtream(let xtream)):
            guard var components = URLComponents(url: xtream.serverURL, resolvingAgainstBaseURL: false) else {
                throw XtreamError.invalidServerURL
            }
            components.percentEncodedPath = "/live/\(PercentEncoding.encode(xtream.username))"
                + "/\(PercentEncoding.encode(xtream.password))/\(streamID).\(transportStream ? "ts" : "m3u8")"
            guard let url = components.url else { throw XtreamError.invalidServerURL }
            return url
        case (.xtream, .m3uURL):
            throw StreamURLError.credentialsDoNotMatchChannel
        }
    }
}
