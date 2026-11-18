import Foundation

public enum ProfileKind: String, Sendable, Codable {
    case xtream
    case m3u
}

/// Eine gespeicherte Quelle. Enthält bewusst keine Zugangsdaten: die liegen
/// ausschliesslich im `CredentialStore` (Keychain), verknüpft über `id`.
public struct Profile: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: ProfileKind
    /// Erkennt dieselbe Quelle auf anderen Geräten (`SourceFingerprint`); enthält keine Zugangsdaten.
    public var sourceFingerprint: String?

    public init(id: UUID = UUID(), name: String, kind: ProfileKind, sourceFingerprint: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sourceFingerprint = sourceFingerprint
    }
}

/// Was ein anderes Gerät braucht, um Live TV dort fortzusetzen, wo man aufgehört hat.
public struct LiveResumeState: Sendable, Hashable, Codable {
    public var channelID: String
    /// Echte Uhrzeit (beim Anbieter) der zuletzt gesehenen Stelle, wenn eine Aufnahme/Timeshift lief; `nil` = live.
    public var timeshiftInstant: Date?
    public var updatedAt: Date

    public init(channelID: String, timeshiftInstant: Date? = nil, updatedAt: Date = Date()) {
        self.channelID = channelID
        self.timeshiftInstant = timeshiftInstant
        self.updatedAt = updatedAt
    }
}
