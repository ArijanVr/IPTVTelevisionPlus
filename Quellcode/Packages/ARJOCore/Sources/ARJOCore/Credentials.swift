import Foundation

public struct XtreamCredentials: Sendable, Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Nur Schema, Host und Port (siehe `XtreamServerURL.normalize`).
    public var serverURL: URL
    public var username: String
    public var password: String

    public init(serverURL: URL, username: String, password: String) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
    }

    public var description: String { "XtreamCredentials(server: \(serverURL.host() ?? "?"), username: ***, password: ***)" }
    public var debugDescription: String { description }
}

/// Alles, was zum Abrufen einer Quelle geheim ist. Eine M3U-URL gehört dazu,
/// weil Anbieter Zugangstokens in der URL mitgeben.
public enum SourceCredentials: Sendable, Hashable, Codable {
    case xtream(XtreamCredentials)
    case m3uURL(URL)
}

public protocol CredentialStore: Sendable {
    func save(_ credentials: SourceCredentials, for profileID: UUID) throws
    func load(for profileID: UUID) throws -> SourceCredentials?
    func delete(for profileID: UUID) throws
}
