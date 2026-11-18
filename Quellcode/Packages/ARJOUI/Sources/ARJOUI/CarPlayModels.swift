import ARJOCore
import Foundation

/// Zustand der CarPlay-Verbindung aus Sicht der App. Ob das Fahrzeug Video gerade zeigen darf, entscheidet das System (Wiedergaberichtlinie);
/// die API meldet nur, ob die Sitzung Video grundsätzlich unterstützt.
public enum CarPlayVideoState: Equatable, Sendable {
    case disconnected
    case connectedAudioOnly
    case connectedVideoCapable

    public static func resolve(isConnected: Bool, supportsVideo: Bool) -> CarPlayVideoState {
        guard isConnected else { return .disconnected }
        return supportsVideo ? .connectedVideoCapable : .connectedAudioOnly
    }

    public var presentsVideo: Bool { self == .connectedVideoCapable }
}

/// Eine Zeile in einer CarPlay-Liste.
public struct CarPlayRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let logoURL: URL?
}

/// Fahrerablenkung begrenzen (CarPlay-Richtlinien): kurze Listen, kurze Texte, nur ein Blick pro Zeile.
public enum CarPlayDrivingLimits {
    /// Obergrenze für Zeilen pro Liste. Das System meldet selbst weniger, wenn Listen eingeschränkt sind; die App fügt keine eigenen Zusatzstufen hinzu.
    public static let preferredMaxItems = 12

    public static func itemLimit(systemMaximum: Int) -> Int {
        max(1, min(systemMaximum, preferredMaxItems))
    }

    /// Kürzt einen Text auf `maxLength` Zeichen mit Auslassungszeichen, damit eine Zeile mit einem Blick lesbar bleibt.
    public static func glanceable(_ text: String, maxLength: Int = 36) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

enum CarPlayRows {
    /// Höchstens `limit` Zeilen, ohne Doppelte, mit der laufenden Sendung als Untertitel.
    @MainActor
    static func make(from channels: [Channel], limit: Int, name: (Channel) -> String, nowTitle: (Channel) -> String?) -> [CarPlayRow] {
        var seen = Set<String>()
        return channels
            .filter { seen.insert($0.id).inserted }
            .prefix(max(limit, 0))
            .map { CarPlayRow(id: $0.id, title: CarPlayDrivingLimits.glanceable(name($0)), subtitle: nowTitle($0).map { CarPlayDrivingLimits.glanceable($0) }, logoURL: $0.logoURL) }
    }
}
