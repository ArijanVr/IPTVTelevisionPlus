import Foundation

public enum XtreamServerURL {
    /// Macht aus Eingaben wie `example.com:8080`, `http://example.com:8080/c/` oder
    /// `https://example.com/player_api.php?x=1` eine Basis-URL aus Schema, Host und Port.
    /// Ohne Schema wird `http` angenommen, weil die meisten Anbieter kein TLS bieten.
    public static func normalize(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw XtreamError.invalidServerURL }

        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let parsed = URLComponents(string: withScheme),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty
        else { throw XtreamError.invalidServerURL }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host.lowercased()
        components.port = parsed.port
        guard let url = components.url else { throw XtreamError.invalidServerURL }
        return url
    }
}
