import Foundation

/// Ein Eintrag einer M3U-Playlist (Sender, Film oder Episode, je nach Anbieter).
public struct PlaylistEntry: Sendable, Hashable, Codable {
    public var name: String
    public var url: URL
    public var tvgID: String?
    public var tvgName: String?
    public var logoURL: URL?
    public var groupTitle: String?
    public var catchupType: String?
    public var catchupDays: Int?
    public var catchupSource: String?
    /// `tvg-chno` aus der Playlist.
    public var channelNumber: Int?

    public init(
        name: String,
        url: URL,
        tvgID: String? = nil,
        tvgName: String? = nil,
        logoURL: URL? = nil,
        groupTitle: String? = nil,
        catchupType: String? = nil,
        catchupDays: Int? = nil,
        catchupSource: String? = nil,
        channelNumber: Int? = nil
    ) {
        self.name = name
        self.url = url
        self.tvgID = tvgID
        self.tvgName = tvgName
        self.logoURL = logoURL
        self.groupTitle = groupTitle
        self.catchupType = catchupType
        self.catchupDays = catchupDays
        self.catchupSource = catchupSource
        self.channelNumber = channelNumber
    }
}
