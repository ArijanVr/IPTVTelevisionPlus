import ARJOCore
import Foundation

enum XMLTVStream {
    /// Entpackt die Datei bei Bedarf (gzip) und liefert nur Sendungen der erlaubten Sender im Zeitfenster.
    /// Die Datei gehört danach dem Strom und wird nach dem Lesen gelöscht.
    static func programmes(
        in downloaded: URL, allowedChannelIDs: Set<String>, window: DateInterval
    ) async throws -> AsyncThrowingStream<EPGProgramme, Error> {
        let readable: URL
        do {
            readable = try unpackedIfNeeded(downloaded)
        } catch {
            try? FileManager.default.removeItem(at: downloaded)
            throw error
        }

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                // Vor dem Beenden des Stroms löschen, damit nach dem Import keine Datei übrig bleibt.
                var parseError: Error?
                do {
                    try XMLTVParser.parse(
                        fileURL: readable,
                        onChannel: { _ in },
                        onProgramme: { programme in
                            guard allowedChannelIDs.contains(programme.channelID),
                                  programme.stop > window.start, programme.start < window.end
                            else { return }
                            continuation.yield(programme)
                        }
                    )
                } catch {
                    parseError = error
                }
                try? FileManager.default.removeItem(at: readable)
                continuation.finish(throwing: parseError)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func unpackedIfNeeded(_ file: URL) throws -> URL {
        guard try Gzip.isGzipped(file) else { return file }
        let unpacked = FileManager.default.temporaryDirectory.appendingPathComponent("arjo-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try Gzip.decompress(from: file, to: unpacked)
        } catch {
            try? FileManager.default.removeItem(at: unpacked)
            throw error
        }
        return unpacked
    }
}
