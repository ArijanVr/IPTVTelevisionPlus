import Foundation

public struct XtreamAccountInfo: Sendable, Hashable {
    public var username: String
    public var status: String
    /// `nil` bei unbegrenzten Konten.
    public var expirationDate: Date?
    public var isTrial: Bool
    public var activeConnections: Int?
    public var maxConnections: Int?
    public var allowedOutputFormats: [String]
    public var serverTimeZone: String?

    public init(
        username: String,
        status: String,
        expirationDate: Date? = nil,
        isTrial: Bool = false,
        activeConnections: Int? = nil,
        maxConnections: Int? = nil,
        allowedOutputFormats: [String] = [],
        serverTimeZone: String? = nil
    ) {
        self.username = username
        self.status = status
        self.expirationDate = expirationDate
        self.isTrial = isTrial
        self.activeConnections = activeConnections
        self.maxConnections = maxConnections
        self.allowedOutputFormats = allowedOutputFormats
        self.serverTimeZone = serverTimeZone
    }
}

public protocol XtreamAuthenticating: Sendable {
    /// Prüft die Zugangsdaten beim Server und liefert die Kontoinformationen.
    func authenticate() async throws -> XtreamAccountInfo
}
