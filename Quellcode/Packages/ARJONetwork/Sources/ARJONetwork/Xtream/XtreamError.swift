import Foundation

/// Enthält absichtlich keine URLs oder Zugangsdaten, damit Fehler ohne Risiko angezeigt
/// und geloggt werden können.
public enum XtreamError: Error, Equatable, LocalizedError {
    case invalidServerURL
    case invalidCredentials
    case accountInactive(status: String)
    case httpStatus(Int)
    case network(URLError.Code)
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            String(localized: "Die Server-Adresse ist ungültig.")
        case .invalidCredentials:
            String(localized: "Benutzername oder Passwort sind falsch.")
        case .accountInactive(let status):
            String(localized: "Das Konto ist nicht aktiv (Status: \(status)).")
        case .httpStatus(let code):
            String(localized: "Der Server hat mit Fehler \(code) geantwortet.")
        case .network(let code):
            switch code {
            case .notConnectedToInternet: String(localized: "Keine Internetverbindung.")
            case .timedOut: String(localized: "Der Server antwortet nicht (Zeitüberschreitung).")
            case .cannotFindHost: String(localized: "Der Server wurde nicht gefunden. Prüfe die Adresse.")
            default: String(localized: "Der Server ist nicht erreichbar.")
            }
        case .unexpectedResponse:
            String(localized: "Der Server hat keine gültige Xtream-Antwort geliefert. Prüfe die Adresse.")
        }
    }
}
