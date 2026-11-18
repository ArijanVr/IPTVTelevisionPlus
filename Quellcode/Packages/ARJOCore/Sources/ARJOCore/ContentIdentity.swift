import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Kennungen für Inhalte aus M3U-Playlists, die über Geräte und neu geladene Playlists hinweg gleich bleiben.
///
/// Stream-Adressen enthalten oft Zugangsdaten (`/movie/<Benutzer>/<Passwort>/123.mkv`) oder kurzlebige Tokens
/// (`?token=…`). Kennungen dürfen deshalb nie die ganze Adresse sein: Sie würden sich bei jedem neuen Token ändern
/// und Zugangsdaten in die iCloud-Datenbank tragen. Stattdessen zählt der «Fundort» ohne Geheimnisse.
public enum ContentIdentity {
    /// Pfadsegmente, nach denen bei Xtream-Adressen Benutzer und Passwort folgen.
    private static let xtreamFolders: Set<String> = ["live", "movie", "series"]
    /// Query-Parameter, die nichts über den Inhalt sagen, sondern Zugang oder Gültigkeit regeln.
    private static let volatileQueryNames: Set<String> = [
        "password", "pass", "pwd", "token", "auth", "key", "sig", "signature", "expires", "exp",
        "session", "sid", "wmsauthsign", "hdnts", "hdnea", "policy", "key-pair-id",
    ]

    /// Fundort einer Stream-Adresse ohne Zugangsdaten:
    /// - Xtream-Muster `/<live|movie|series>/<Benutzer>/<Passwort>/<ID>.<Endung>` → `movie/<ID>` (ohne Host,
    ///   damit ein Wechsel der Server-Adresse des Anbieters nichts ändert).
    /// - sonst Host, Port und Pfad ohne Benutzerangaben, Fragment und Token-Parameter.
    public static func locator(for url: URL) -> String {
        let segments = url.path.split(separator: "/").map(String.init)
        if segments.count == 4, xtreamFolders.contains(segments[0].lowercased()) {
            let file = segments[3]
            let id = file.split(separator: ".").first.map(String.init) ?? file
            return "\(segments[0].lowercased())/\(id)"
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.user = nil
        components.password = nil
        components.fragment = nil
        let kept = (components.queryItems ?? [])
            .filter { !volatileQueryNames.contains($0.name.lowercased()) }
            .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        components.queryItems = kept.isEmpty ? nil : kept
        let host = (components.host ?? "").lowercased()
        let port = components.port.map { ":\($0)" } ?? ""
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(host)\(port)\(components.percentEncodedPath)\(query)"
    }

    /// Kennung eines Films oder einer Episode aus einer Playlist.
    public static func mediaID(for url: URL) -> Int {
        stableHash(locator(for: url))
    }

    /// Kennung eines Live-Senders aus einer Playlist (Präfix, damit sie nie mit einer Xtream-ID zusammenfällt).
    public static func channelID(for url: URL) -> String {
        "m3u-" + String(stableHash(locator(for: url)), radix: 36)
    }

    /// Ältere Versionen nutzten die vollständige Adresse als Sender-Kennung; liefert sie zurück, falls `id` so eine ist.
    public static func legacyChannelURL(in id: String) -> URL? {
        guard id.contains("://"), let url = URL(string: id), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }

    /// Wandelt eine Sender-Kennung älterer Versionen in die aktuelle um; aktuelle Kennungen bleiben unverändert.
    public static func migratedChannelID(_ id: String) -> String {
        legacyChannelURL(in: id).map(channelID(for:)) ?? id
    }

    /// Stabile Zahl aus einem Text (FNV-1a, 62 Bit): bleibt nach jedem Neuladen und auf jedem Gerät gleich.
    public static func stableHash(_ text: String) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash & 0x3FFF_FFFF_FFFF_FFFF)
    }
}

/// Erkennt dieselbe Quelle (dasselbe Anbieter-Konto) auf verschiedenen Geräten, ohne Zugangsdaten zu speichern.
///
/// Xtream: Server und Benutzername, ohne Passwort. M3U: Fundort der Playlist ohne Passwort- und Token-Parameter.
/// Gespeichert und synchronisiert wird nur der SHA-256-Wert.
public enum SourceFingerprint {
    public static func make(for credentials: SourceCredentials) -> String {
        let material: String
        switch credentials {
        case .xtream(let xtream):
            let host = (xtream.serverURL.host() ?? "").lowercased()
            let port = xtream.serverURL.port.map { ":\($0)" } ?? ""
            material = "xtream|\(host)\(port)|\(xtream.username.lowercased())"
        case .m3uURL(let url):
            material = url.isFileURL ? "m3u-file|\(url.lastPathComponent)" : "m3u|\(ContentIdentity.locator(for: url))"
        }
        return sha256(material)
    }

    private static func sha256(_ text: String) -> String {
        #if canImport(CryptoKit)
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        String(ContentIdentity.stableHash(text), radix: 16)
        #endif
    }
}
