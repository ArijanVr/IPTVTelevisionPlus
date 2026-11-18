import ARJOCore
import Foundation
import OSLog
#if os(tvOS)
import TVServices
#endif

/// Legt den Top-Shelf-Stand in einer Datei im App-Group-Container ab, die auch die Top-Shelf-Erweiterung lesen kann.
public struct TopShelfStore: TopShelfPublishing {
    public static let defaultAppGroup = "group.ch.arjo.iptelevision"
    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "topshelf")

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `nil`, wenn die App-Group-Berechtigung fehlt.
    public static func appGroup(_ identifier: String = defaultAppGroup) -> TopShelfStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            .map { TopShelfStore(fileURL: $0.appendingPathComponent("topshelf.json")) }
    }

    public func write(_ snapshot: TopShelfSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    public func read() throws -> TopShelfSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TopShelfSnapshot.self, from: Data(contentsOf: fileURL))
    }

    public func publish(_ snapshot: TopShelfSnapshot) {
        do {
            try write(snapshot)
            #if os(tvOS)
            TVTopShelfContentProvider.topShelfContentDidChange()
            #endif
        } catch {
            Self.log.error("Top Shelf nicht geschrieben: \(error.localizedDescription)")
        }
    }
}
