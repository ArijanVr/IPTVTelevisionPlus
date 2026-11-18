import ARJOCore
import Foundation

public enum M3UPlaylistError: Error, Equatable, LocalizedError {
    case noEPGSource
    case httpStatus(Int)
    case network(URLError.Code)

    public var errorDescription: String? {
        switch self {
        case .noEPGSource: String(localized: "Die Playlist nennt keine EPG-Quelle.")
        case .httpStatus(let code): String(localized: "Der Server hat mit Fehler \(code) geantwortet.")
        case .network(let code):
            code == .notConnectedToInternet ? String(localized: "Keine Internetverbindung.") : String(localized: "Die Playlist ist nicht erreichbar.")
        }
    }
}

public extension M3UStreamParser {
    /// Liest nur die erste Zeile (`#EXTM3U …`), ohne die ganze Playlist zu laden.
    /// Prüft damit zugleich, dass die Adresse erreichbar ist und eine M3U-Playlist liefert.
    static func readHeader(of url: URL) async throws -> M3UHeader {
        if url.isFileURL {
            for try await line in url.lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return try header(fromFirstLine: line)
            }
            throw M3UParseError.missingHeader
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                throw M3UPlaylistError.httpStatus(status)
            }
            for try await line in bytes.lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return try header(fromFirstLine: line)
            }
            throw M3UParseError.missingHeader
        } catch let error as URLError {
            throw M3UPlaylistError.network(error.code)
        }
    }
}

/// Eine M3U-Playlist (URL oder lokale Datei) als Quelle für Sender und – über `url-tvg` im Kopf – für das EPG.
public struct M3UPlaylistSource: LiveCatalogStreaming, EPGProviding {
    private let url: URL
    private let download: @Sendable (URLRequest) async throws -> URL

    public init(url: URL, download: @escaping @Sendable (URLRequest) async throws -> URL = { try await FileDownloader.download($0) }) {
        self.url = url
        self.download = download
    }

    public func channelStream() async throws -> AsyncThrowingStream<Channel, Error> {
        let isTemporary = !url.isFileURL
        let file = isTemporary ? try await download(URLRequest(url: url)) : url

        return AsyncThrowingStream { continuation in
            let task = Task {
                var failure: Error?
                do {
                    // Filme und Serien der Playlist gehören nicht in die Senderliste.
                    _ = try await M3UStreamParser().parse(fileURL: file) { entry in
                        if M3UMediaClassifier.classify(entry) == .live { continuation.yield(Channel(entry: entry)) }
                    }
                } catch {
                    failure = error
                }
                if isTemporary { try? FileManager.default.removeItem(at: file) }
                continuation.finish(throwing: failure)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func programmes(
        allowedChannelIDs: Set<String>, window: DateInterval
    ) async throws -> AsyncThrowingStream<EPGProgramme, Error> {
        guard let epgURL = try await M3UStreamParser.readHeader(of: url).epgURLs.first else {
            throw M3UPlaylistError.noEPGSource
        }
        let file = epgURL.isFileURL ? try copyToTemporary(epgURL) : try await download(URLRequest(url: epgURL))
        return try await XMLTVStream.programmes(in: file, allowedChannelIDs: allowedChannelIDs, window: window)
    }

    private func copyToTemporary(_ source: URL) throws -> URL {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("arjo-\(UUID().uuidString).xml")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
}
