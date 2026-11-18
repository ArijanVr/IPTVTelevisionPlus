import Foundation

/// Sicherung der Einstellungen, Favoriten, Ordner und des Wiedergabestands.
/// Enthält bewusst weder Zugangsdaten noch die PIN: die liegen nur in der Keychain.
public struct BackupDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var createdAt: Date
    public var settings: AppSettings
    public var profiles: [ProfileBackup]

    public init(version: Int = BackupDocument.currentVersion, createdAt: Date = Date(), settings: AppSettings, profiles: [ProfileBackup]) {
        self.version = version
        self.createdAt = createdAt
        self.settings = settings
        self.profiles = profiles
    }
}

public struct ProfileBackup: Codable, Equatable, Sendable {
    public var profile: Profile
    public var preferences: [Preference]
    public var folders: [ChannelFolder]
    public var progress: [WatchProgress]

    public init(profile: Profile, preferences: [Preference], folders: [ChannelFolder], progress: [WatchProgress]) {
        self.profile = profile
        self.preferences = preferences
        self.folders = folders
        self.progress = progress
    }
}
