import Foundation

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    private static let defaultTimeout: TimeInterval = 20
    /// Eine gemeinsame Session statt einer neuen pro Client: Sessions werden nie invalidiert und würden sonst
    /// bei jedem Abruf (Login, Senderliste, EPG, Serverzeit) Ressourcen bis zum Ende der App belegen.
    private static let shared = makeSession(timeout: defaultTimeout)

    /// Ephemere Session: keine Cookies, kein Disk-Cache. URLs enthalten Zugangsdaten
    /// und dürfen nicht im URL-Cache landen.
    public init(timeout: TimeInterval = 20) {
        session = timeout == Self.defaultTimeout ? Self.shared : Self.makeSession(timeout: timeout)
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
