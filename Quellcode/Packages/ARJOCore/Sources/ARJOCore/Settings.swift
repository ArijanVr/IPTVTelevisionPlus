import Foundation

public enum AccentChoice: String, Sendable, Codable, CaseIterable {
    /// Brand-Standard: Schwarz im hellen, Weiss im dunklen Erscheinungsbild.
    case mono, signal, blue, green, red, purple, orange

    /// Der frühere Standard «Gold» gehört nicht mehr zur Marke und wird zu «Monochrom».
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = raw == "gold" ? .mono : (AccentChoice(rawValue: raw) ?? .mono)
    }

    /// Farbe als 0xRRGGBB.
    public var hex: UInt32 {
        switch self {
        case .mono: 0x090A0A
        case .signal: 0xFC5F39
        case .blue: 0x4A90E2
        case .green: 0x3FB67A
        case .red: 0xE5534B
        case .purple: 0x9B6BDF
        case .orange: 0xE8873A
        }
    }

    public var title: String {
        switch self {
        case .mono: String(localized: "Monochrom")
        case .signal: String(localized: "Glut")
        case .blue: String(localized: "Blau")
        case .green: String(localized: "Grün")
        case .red: String(localized: "Rot")
        case .purple: String(localized: "Violett")
        case .orange: String(localized: "Orange")
        }
    }
}

public enum AppearanceMode: String, Sendable, Codable, CaseIterable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Hell")
        case .dark: String(localized: "Dunkel")
        }
    }
}

public enum AspectMode: String, Sendable, Codable, CaseIterable {
    /// Ganzes Bild, bei Bedarf mit Rändern.
    case fit
    /// Füllt den Bildschirm, schneidet bei Bedarf ab.
    case fill

    public var title: String { self == .fit ? String(localized: "Einpassen") : String(localized: "Füllen") }
}

/// Grösse der Senderkacheln in Reihen und Rastern.
public enum TileSize: String, Sendable, Codable, CaseIterable {
    case compact, regular, large

    public var title: String {
        switch self {
        case .compact: String(localized: "Kompakt")
        case .regular: String(localized: "Normal")
        case .large: String(localized: "Gross")
        }
    }

    /// Faktor auf die Grundgrösse der Kachel.
    public var scale: Double {
        switch self {
        case .compact: 0.8
        case .regular: 1
        case .large: 1.25
        }
    }
}

/// Reihen der Startseite, deren Reihenfolge und Sichtbarkeit der Nutzer selbst bestimmt.
public enum HomeSection: String, Sendable, Codable, CaseIterable, Identifiable {
    case hero, continueWatching, onAir, lastChannel, favorites, folders, categories, movies, series

    public var id: Self { self }

    public var title: String {
        switch self {
        case .hero: String(localized: "Titelbild")
        case .continueWatching: String(localized: "Weiterschauen")
        case .onAir: String(localized: "Jetzt im TV")
        case .lastChannel: String(localized: "Zuletzt gesehen")
        case .favorites: String(localized: "Favoriten")
        case .folders: String(localized: "Eigene Ordner")
        case .categories: String(localized: "Kategorien")
        case .movies: String(localized: "Neue Filme")
        case .series: String(localized: "Neue Serien")
        }
    }

    public var symbol: String {
        switch self {
        case .hero: "rectangle.inset.filled"
        case .continueWatching: "play.circle"
        case .onAir: "dot.radiowaves.left.and.right"
        case .lastChannel: "clock.arrow.circlepath"
        case .favorites: "star"
        case .folders: "folder"
        case .categories: "square.grid.2x2"
        case .movies: "film"
        case .series: "rectangle.stack"
        }
    }

    /// Ergänzt fehlende (z. B. in späteren Versionen neu hinzugekommene) Reihen am Ende und entfernt Doppelte.
    public static func normalized(_ order: [HomeSection]) -> [HomeSection] {
        var seen = Set<HomeSection>()
        let known = order.filter { seen.insert($0).inserted }
        return known + allCases.filter { !seen.contains($0) }
    }
}

/// Einstellungen, die auf allen Geräten gelten (später per iCloud synchronisiert).
/// Alle Felder haben Standardwerte, damit ältere gespeicherte Stände weiter lesbar bleiben.
public struct AppSettings: Sendable, Codable, Equatable {
    public static let epgOffsetRangeMinutes = -720...720
    public static let bufferChoices: [Double] = [1.5, 4, 8, 15]
    /// Ab diesem Alter aktualisiert die App Sender-, Film- und Serienlisten automatisch.
    public static let autoRefreshAge: TimeInterval = 24 * 3_600

    public var accent: AccentChoice = .mono
    public var appearance: AppearanceMode = .dark
    /// Verschiebt alle EPG-Zeiten (z. B. wenn der Anbieter in einer anderen Zeitzone sendet).
    public var epgOffsetMinutes = 0
    /// `nil` = Zeitzone des Geräts.
    public var timeZoneID: String?
    public var bufferSeconds: Double = 4
    public var aspect: AspectMode = .fit
    public var resumeLastChannelOnLaunch = false
    public var autoRefresh = true
    /// Spielt nach einer Episode automatisch die nächste ab.
    public var autoPlayNextEpisode = true
    /// Zeigt «Weiterschauen» im Top Shelf von Apple TV.
    public var topShelfEnabled = true
    /// Pro Profil-ID gesperrte Gruppen (Schlüssel siehe `GroupKey`).
    public var lockedGroups: [String: [String]] = [:]
    /// Zeigt den Sendernamen unter den Logo-Kacheln.
    public var showsChannelNames = true
    public var tileSize: TileSize = .regular
    /// Reihenfolge der Startseite.
    public var homeOrder: [HomeSection] = HomeSection.allCases
    /// Ausgeblendete Reihen der Startseite.
    public var hiddenHomeSections: Set<HomeSection> = []

    public init() {}

    /// Sichtbare Reihen der Startseite in der eigenen Reihenfolge.
    public var visibleHomeSections: [HomeSection] {
        HomeSection.normalized(homeOrder).filter { !hiddenHomeSections.contains($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case accent, appearance, epgOffsetMinutes, timeZoneID, bufferSeconds, aspect, resumeLastChannelOnLaunch, autoRefresh, autoPlayNextEpisode, topShelfEnabled, lockedGroups
        case showsChannelNames, tileSize, homeOrder, hiddenHomeSections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? accent
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? appearance
        epgOffsetMinutes = try c.decodeIfPresent(Int.self, forKey: .epgOffsetMinutes) ?? epgOffsetMinutes
        timeZoneID = try c.decodeIfPresent(String.self, forKey: .timeZoneID)
        bufferSeconds = try c.decodeIfPresent(Double.self, forKey: .bufferSeconds) ?? bufferSeconds
        aspect = try c.decodeIfPresent(AspectMode.self, forKey: .aspect) ?? aspect
        resumeLastChannelOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .resumeLastChannelOnLaunch) ?? resumeLastChannelOnLaunch
        autoRefresh = try c.decodeIfPresent(Bool.self, forKey: .autoRefresh) ?? autoRefresh
        autoPlayNextEpisode = try c.decodeIfPresent(Bool.self, forKey: .autoPlayNextEpisode) ?? autoPlayNextEpisode
        topShelfEnabled = try c.decodeIfPresent(Bool.self, forKey: .topShelfEnabled) ?? topShelfEnabled
        lockedGroups = try c.decodeIfPresent([String: [String]].self, forKey: .lockedGroups) ?? lockedGroups
        showsChannelNames = try c.decodeIfPresent(Bool.self, forKey: .showsChannelNames) ?? showsChannelNames
        tileSize = (try? c.decodeIfPresent(TileSize.self, forKey: .tileSize)) ?? tileSize
        // Unbekannte Werte (aus neueren Versionen) überspringen statt die ganzen Einstellungen zu verwerfen.
        if let raw = try? c.decodeIfPresent([String].self, forKey: .homeOrder) {
            homeOrder = HomeSection.normalized(raw.compactMap(HomeSection.init(rawValue:)))
        }
        if let raw = try? c.decodeIfPresent([String].self, forKey: .hiddenHomeSections) {
            hiddenHomeSections = Set(raw.compactMap(HomeSection.init(rawValue:)))
        }
    }

    public var timeZone: TimeZone {
        timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    public var epgOffset: TimeInterval { TimeInterval(epgOffsetMinutes * 60) }
}

/// Bereiche, in denen Gruppen gesperrt werden können.
public enum GroupArea: String, Sendable, Codable, CaseIterable {
    case live, movie, series

    public var title: String {
        switch self {
        case .live: String(localized: "Live TV")
        case .movie: String(localized: "Filme")
        case .series: String(localized: "Serien")
        }
    }
}

public enum GroupKey {
    public static func make(_ area: GroupArea, _ name: String) -> String { "\(area.rawValue):\(name)" }
}

public protocol SettingsRepository: Sendable {
    func load() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
}

/// PIN der Kindersicherung. Gespeichert wird nie die PIN selbst, sondern ein gesalzener Hash.
public protocol PINStore: Sendable {
    var hasPIN: Bool { get throws }
    func setPIN(_ pin: String) throws
    func verify(_ pin: String) throws -> Bool
    func removePIN() throws
}
