import Foundation

enum PercentEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Kodiert alles ausser RFC-3986-„unreserved“. `urlQueryAllowed`/`urlPathAllowed` lassen
    /// `&`, `+` und `/` stehen, die in Benutzernamen und Passwörtern vorkommen können.
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
