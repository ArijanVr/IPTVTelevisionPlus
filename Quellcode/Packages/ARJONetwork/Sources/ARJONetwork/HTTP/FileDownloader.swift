import Foundation

public enum FileDownloader {
    /// Lädt eine (grosse) Datei direkt auf die Platte und liefert einen Pfad, den der Aufrufer löschen muss.
    /// Fehler enthalten keine URL, weil sie Zugangsdaten enthalten kann.
    public static func download(_ request: URLRequest) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await session.download(for: request)
        } catch let error as URLError {
            throw XtreamError.network(error.code)
        }

        let target = FileManager.default.temporaryDirectory.appendingPathComponent("arjo-\(UUID().uuidString).download")
        try FileManager.default.moveItem(at: temporary, to: target)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: target)
            throw status == 401 || status == 403 ? XtreamError.invalidCredentials : XtreamError.httpStatus(status)
        }
        return target
    }
}
