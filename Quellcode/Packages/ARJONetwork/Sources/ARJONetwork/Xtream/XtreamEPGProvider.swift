import ARJOCore
import Foundation

/// Lädt das gesamte XMLTV-EPG des Anbieters (`xmltv.php`) und liest es als Strom.
public struct XtreamEPGProvider: EPGProviding {
    private let credentials: XtreamCredentials
    private let download: @Sendable (URLRequest) async throws -> URL

    public init(
        credentials: XtreamCredentials,
        download: @escaping @Sendable (URLRequest) async throws -> URL = { try await FileDownloader.download($0) }
    ) {
        self.credentials = credentials
        self.download = download
    }

    public func programmes(
        allowedChannelIDs: Set<String>, window: DateInterval
    ) async throws -> AsyncThrowingStream<EPGProgramme, Error> {
        let downloaded = try await download(try makeRequest())
        return try await XMLTVStream.programmes(in: downloaded, allowedChannelIDs: allowedChannelIDs, window: window)
    }

    private func makeRequest() throws -> URLRequest {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw XtreamError.invalidServerURL
        }
        components.path = "/xmltv.php"
        components.percentEncodedQuery = "username=\(PercentEncoding.encode(credentials.username))"
            + "&password=\(PercentEncoding.encode(credentials.password))"
        guard let url = components.url else { throw XtreamError.invalidServerURL }
        return URLRequest(url: url)
    }
}
