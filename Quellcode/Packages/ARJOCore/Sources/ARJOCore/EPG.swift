import Foundation

/// Sender-Eintrag aus einer XMLTV-Datei. `id` entspricht `tvg-id` der Playlist.
public struct EPGChannel: Sendable, Hashable, Codable {
    public var id: String
    public var displayName: String
    public var iconURL: URL?

    public init(id: String, displayName: String, iconURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.iconURL = iconURL
    }
}

/// Eine Sendung im Programmführer.
public struct EPGProgramme: Sendable, Hashable, Codable {
    public var channelID: String
    public var start: Date
    public var stop: Date
    public var title: String
    public var subtitle: String?
    public var description: String?
    public var category: String?
    public var iconURL: URL?

    public init(
        channelID: String,
        start: Date,
        stop: Date,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        category: String? = nil,
        iconURL: URL? = nil
    ) {
        self.channelID = channelID
        self.start = start
        self.stop = stop
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.category = category
        self.iconURL = iconURL
    }

    public func isAiring(at date: Date) -> Bool {
        start <= date && date < stop
    }

    /// Anteil der Sendung, der zu `date` vorbei ist (0 bis 1).
    public func progress(at date: Date) -> Double {
        let length = stop.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / length, 0), 1)
    }
}

public struct NowNext: Sendable, Hashable {
    public var now: EPGProgramme?
    public var next: EPGProgramme?

    public init(now: EPGProgramme? = nil, next: EPGProgramme? = nil) {
        self.now = now
        self.next = next
    }
}

public extension EPGProgramme {
    /// Verschiebt Beginn und Ende (EPG-Zeitversatz).
    func shifted(by offset: TimeInterval) -> EPGProgramme {
        guard offset != 0 else { return self }
        var copy = self
        copy.start = start.addingTimeInterval(offset)
        copy.stop = stop.addingTimeInterval(offset)
        return copy
    }
}
