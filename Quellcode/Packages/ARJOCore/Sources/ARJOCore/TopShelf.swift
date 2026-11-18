import Foundation

/// Ein Eintrag im Top Shelf von Apple TV («Weiterschauen»).
public struct TopShelfItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var imageURL: URL?
    /// Anteil 0 bis 1.
    public var progress: Double
    public var deepLink: URL

    public init(id: String, title: String, subtitle: String? = nil, imageURL: URL? = nil, progress: Double, deepLink: URL) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.progress = progress
        self.deepLink = deepLink
    }
}

/// Was die App dem Top-Shelf-Erweiterungsprozess übergibt. Enthält nur Titel, Bild-Adressen und Fortschritt,
/// keine Zugangsdaten.
public struct TopShelfSnapshot: Codable, Equatable, Sendable {
    public var items: [TopShelfItem]
    public var updatedAt: Date

    public init(items: [TopShelfItem], updatedAt: Date = Date()) {
        self.items = items
        self.updatedAt = updatedAt
    }
}

public protocol TopShelfPublishing: Sendable {
    func publish(_ snapshot: TopShelfSnapshot)
}

/// Adressen der Form `arjotv://play?item=movie-123`.
public enum DeepLink {
    public static let scheme = "arjotv"

    public static func play(itemID: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "play"
        components.queryItems = [URLQueryItem(name: "item", value: itemID)]
        return components.url ?? URL(string: "\(scheme)://play")!
    }

    public static func playItemID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "play",
              let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "item" })?.value,
              !item.isEmpty
        else { return nil }
        return item
    }
}
