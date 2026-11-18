import ARJOCore
import Foundation

public enum CatchupError: Error, Equatable, LocalizedError {
    case notSupported
    case invalidAddress

    public var errorDescription: String? {
        switch self {
        case .notSupported: String(localized: "Dieser Sender bietet keine Aufnahmen zum Zurückspulen an.")
        case .invalidAddress: String(localized: "Die Adresse der Aufnahme konnte nicht gebildet werden.")
        }
    }
}

/// Baut die Adresse einer vergangenen Sendung (Catch-up/Timeshift).
/// - Xtream: `/timeshift/<Benutzer>/<Passwort>/<Minuten>/<Jahr-Monat-Tag:Stunde-Minute>/<ID>.m3u8`,
///   die Uhrzeit in der Zeitzone des Servers.
/// - M3U: je nach `catchup`-Art (`default`/`flussonic`, `append`, `shift`) mit der Vorlage `catchup-source`.
public enum CatchupURLBuilder {
    /// - Parameters:
    ///   - start: Beginn der Sendung (echte Zeit des Anbieters, ohne EPG-Zeitversatz).
    ///   - now: Zeitpunkt der Anfrage, für `lutc`/`timestamp`/`offset`.
    ///   - serverTimeZone: Zeitzone des Xtream-Servers; ohne Angabe UTC.
    public static func url(
        for channel: Channel,
        credentials: SourceCredentials,
        start: Date,
        end: Date,
        now: Date = Date(),
        serverTimeZone: TimeZone? = nil
    ) throws -> URL {
        guard channel.supportsCatchup else { throw CatchupError.notSupported }
        let duration = max(Int(end.timeIntervalSince(start)), 60)

        switch (channel.source, credentials) {
        case (.xtream(let streamID), .xtream(let xtream)):
            return try xtreamURL(streamID: streamID, credentials: xtream, start: start, duration: duration, timeZone: serverTimeZone ?? TimeZone(identifier: "UTC")!)
        case (.url(let streamURL), _):
            return try playlistURL(channel: channel, streamURL: streamURL, start: start, duration: duration, now: now)
        case (.xtream, .m3uURL):
            throw StreamURLError.credentialsDoNotMatchChannel
        }
    }

    // MARK: Xtream

    private static func xtreamURL(
        streamID: Int, credentials: XtreamCredentials, start: Date, duration: Int, timeZone: TimeZone
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd:HH-mm"
        let minutes = (duration + 59) / 60

        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw CatchupError.invalidAddress
        }
        components.percentEncodedPath = "/timeshift/\(PercentEncoding.encode(credentials.username))"
            + "/\(PercentEncoding.encode(credentials.password))/\(minutes)"
            + "/\(formatter.string(from: start).replacingOccurrences(of: ":", with: "%3A"))/\(streamID).m3u8"
        guard let url = components.url else { throw CatchupError.invalidAddress }
        return url
    }

    // MARK: M3U

    private static func playlistURL(channel: Channel, streamURL: URL, start: Date, duration: Int, now: Date) throws -> URL {
        let startEpoch = Int(start.timeIntervalSince1970)
        let type = (channel.catchupType ?? "default").lowercased()
        let template = channel.catchupTemplate.flatMap { $0.isEmpty ? nil : $0 }

        let text: String
        switch (type, template) {
        case ("append", let template?):
            text = streamURL.absoluteString + expand(template, start: start, duration: duration, now: now)
        case ("append", nil), ("shift", nil), ("timeshift", nil):
            let separator = streamURL.query == nil ? "?" : "&"
            text = streamURL.absoluteString + "\(separator)utc=\(startEpoch)&lutc=\(Int(now.timeIntervalSince1970))"
        case ("shift", let template?), ("timeshift", let template?):
            let expanded = expand(template, start: start, duration: duration, now: now)
            text = expanded.contains("://") ? expanded : streamURL.absoluteString + expanded
        case (_, let template?):
            let expanded = expand(template, start: start, duration: duration, now: now)
            text = expanded.contains("://") ? expanded : streamURL.absoluteString + expanded
        case (_, nil):
            // Flussonic: <Basis>/video-<Beginn>-<Dauer>.m3u8 statt index.m3u8 bzw. mpegts.
            guard ["index.m3u8", "mpegts", "video.m3u8", "playlist.m3u8"].contains(streamURL.lastPathComponent),
                  var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false)
            else { throw CatchupError.invalidAddress }
            components.path = (components.path as NSString).deletingLastPathComponent + "/video-\(startEpoch)-\(duration).m3u8"
            guard let flussonic = components.string else { throw CatchupError.invalidAddress }
            text = flussonic
        }
        guard let url = URL(string: text), url.scheme != nil else { throw CatchupError.invalidAddress }
        return url
    }

    /// Ersetzt die üblichen Platzhalter der Vorlagen (`${start}`, `{utc}`, `{duration}` …).
    static func expand(_ template: String, start: Date, duration: Int, now: Date) -> String {
        let startEpoch = Int(start.timeIntervalSince1970)
        let nowEpoch = Int(now.timeIntervalSince1970)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }

        let values: [String: String] = [
            "start": "\(startEpoch)", "utc": "\(startEpoch)", "timestamp": "\(nowEpoch)", "lutc": "\(nowEpoch)",
            "end": "\(startEpoch + duration)", "utcend": "\(startEpoch + duration)",
            "duration": "\(duration)", "offset": "\(max(nowEpoch - startEpoch, 0))",
            "Y": "\(parts.year ?? 0)", "m": two(parts.month), "d": two(parts.day),
            "H": two(parts.hour), "M": two(parts.minute), "S": two(parts.second),
        ]
        var result = template
        for (name, value) in values {
            result = result.replacingOccurrences(of: "${\(name)}", with: value)
            result = result.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return result
    }
}
