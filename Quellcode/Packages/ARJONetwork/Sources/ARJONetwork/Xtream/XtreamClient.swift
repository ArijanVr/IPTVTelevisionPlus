import ARJOCore
import Foundation

public struct XtreamClient: XtreamAuthenticating, LiveChannelProviding {
    private let credentials: XtreamCredentials
    private let http: HTTPClient

    public init(credentials: XtreamCredentials, http: HTTPClient = URLSessionHTTPClient()) {
        self.credentials = credentials
        self.http = http
    }

    public func authenticate() async throws -> XtreamAccountInfo {
        let data = try await perform(action: nil)

        let decoded = try? Self.decoder.decode(XtreamLoginResponse.self, from: data)
        guard let user = decoded?.userInfo else { throw XtreamError.unexpectedResponse }

        if let auth = user.auth?.value, auth == "0" || auth.lowercased() == "false" {
            throw XtreamError.invalidCredentials
        }
        guard let username = user.username?.value else { throw XtreamError.unexpectedResponse }

        let status = user.status?.value ?? "Active"
        guard status.lowercased() == "active" else { throw XtreamError.accountInactive(status: status) }

        return XtreamAccountInfo(
            username: username,
            status: status,
            expirationDate: user.expDate.flatMap { TimeInterval($0.value) }.map(Date.init(timeIntervalSince1970:)),
            isTrial: user.isTrial?.value == "1",
            activeConnections: user.activeCons.flatMap { Int($0.value) },
            maxConnections: user.maxConnections.flatMap { Int($0.value) },
            allowedOutputFormats: user.allowedOutputFormats ?? [],
            serverTimeZone: decoded?.serverInfo?.timezone?.value
        )
    }

    /// Sender in Server-Reihenfolge, Gruppennamen aus den Live-Kategorien.
    public func liveChannels() async throws -> [Channel] {
        let categoriesData = try await perform(action: "get_live_categories")
        let streamsData = try await perform(action: "get_live_streams")

        guard let categories = try? Self.decoder.decode([XtreamCategoryDTO].self, from: categoriesData),
              let streams = try? Self.decoder.decode([XtreamLiveStreamDTO].self, from: streamsData)
        else { throw XtreamError.unexpectedResponse }

        let groupNames = Dictionary(
            categories.compactMap { category in
                category.categoryName.map { (category.categoryId.value, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        return streams.compactMap { stream in
            guard let streamID = Int(stream.streamId.value) else { return nil }
            return Channel(
                id: String(streamID),
                name: Self.nonEmpty(stream.name) ?? "Sender \(streamID)",
                source: .xtream(streamID: streamID),
                logoURL: Self.nonEmpty(stream.streamIcon).flatMap { URL(string: $0) },
                groupName: stream.categoryId.flatMap { groupNames[$0.value] } ?? Channel.ungroupedName,
                epgChannelID: Self.nonEmpty(stream.epgChannelId),
                // `tv_archive = 1`: der Anbieter hält `tv_archive_duration` Tage bereit.
                archiveDays: stream.tvArchive?.value == "1" ? max(stream.tvArchiveDuration.flatMap { Int($0.value) } ?? 1, 1) : nil,
                sourceNumber: stream.num.flatMap { Int($0.value) }.flatMap { $0 > 0 ? $0 : nil }
            )
        }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    func perform(action: String?, parameters: [String: String] = [:]) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.data(for: try makeRequest(action: action, parameters: parameters))
        } catch let error as URLError {
            throw XtreamError.network(error.code)
        }

        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 { throw XtreamError.invalidCredentials }
            throw XtreamError.httpStatus(response.statusCode)
        }
        return data
    }

    private func makeRequest(action: String?, parameters: [String: String]) throws -> URLRequest {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw XtreamError.invalidServerURL
        }
        components.path = "/player_api.php"
        // URLQueryItem lässt `&`, `+` und `=` in Werten unkodiert; Passwörter brauchen sie kodiert.
        var query = "username=\(PercentEncoding.encode(credentials.username))"
            + "&password=\(PercentEncoding.encode(credentials.password))"
        if let action { query += "&action=\(action)" }
        for (key, value) in parameters.sorted(by: { $0.key < $1.key }) {
            query += "&\(key)=\(PercentEncoding.encode(value))"
        }
        components.percentEncodedQuery = query
        guard let url = components.url else { throw XtreamError.invalidServerURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
