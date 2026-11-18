import ARJOCore
import Foundation

public struct M3UHeader: Sendable, Equatable {
    /// EPG-URLs aus `url-tvg` bzw. `x-tvg-url` im `#EXTM3U`-Kopf.
    public var epgURLs: [URL]
}

public struct M3UParseResult: Sendable, Equatable {
    public var header: M3UHeader
    public var entryCount: Int
    /// Einträge ohne `#EXTINF` oder mit ungültiger URL.
    public var skippedCount: Int
}

public enum M3UParseError: Error, Equatable, LocalizedError {
    case missingHeader

    public var errorDescription: String? {
        String(localized: "Die Datei ist keine gültige M3U-Playlist.")
    }
}

/// Liest M3U/M3U8 Zeile für Zeile und übergibt jeden Eintrag sofort weiter,
/// damit auch 50'000+ Einträge nie komplett im Speicher liegen müssen.
public struct M3UStreamParser: Sendable {
    public init() {}

    public func parse(
        fileURL: URL,
        onEntry: (PlaylistEntry) async throws -> Void
    ) async throws -> M3UParseResult {
        try await parse(lines: fileURL.lines, onEntry: onEntry)
    }

    public func parse<Lines: AsyncSequence>(
        lines: Lines,
        onEntry: (PlaylistEntry) async throws -> Void
    ) async throws -> M3UParseResult where Lines.Element == String {
        var header: M3UHeader?
        var pending: ExtInfScanner.Result?
        var pendingGroup: String?
        var entryCount = 0
        var skippedCount = 0

        for try await rawLine in lines {
            var line = rawLine
            if header == nil, line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            guard header != nil else {
                header = try Self.header(fromFirstLine: line)
                continue
            }

            if line.hasPrefix("#EXTINF:") {
                pending = ExtInfScanner.scan(line.dropFirst("#EXTINF:".count), hasDuration: true)
                pendingGroup = nil
            } else if line.hasPrefix("#EXTGRP:") {
                pendingGroup = line.dropFirst("#EXTGRP:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#") {
                continue
            } else {
                defer { pending = nil }
                guard let info = pending,
                      let url = URL(string: line), url.scheme != nil
                else {
                    skippedCount += 1
                    continue
                }
                try await onEntry(Self.makeEntry(info: info, group: pendingGroup, url: url))
                entryCount += 1
            }
        }

        guard let header else { throw M3UParseError.missingHeader }
        return M3UParseResult(header: header, entryCount: entryCount, skippedCount: skippedCount)
    }

    static func header(fromFirstLine line: String) throws -> M3UHeader {
        let cleaned = line.hasPrefix("\u{FEFF}") ? String(line.dropFirst()) : line
        guard cleaned.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw M3UParseError.missingHeader }
        return parseHeader(cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseHeader(_ line: String) -> M3UHeader {
        let scanned = ExtInfScanner.scan(line.dropFirst("#EXTM3U".count), hasDuration: false)
        let raw = scanned.attributes["url-tvg"] ?? scanned.attributes["x-tvg-url"] ?? ""
        let urls = raw.split(separator: ",").compactMap {
            URL(string: $0.trimmingCharacters(in: .whitespaces))
        }
        return M3UHeader(epgURLs: urls)
    }

    private static func makeEntry(info: ExtInfScanner.Result, group: String?, url: URL) -> PlaylistEntry {
        let attributes = info.attributes
        let tvgName = nonEmpty(attributes["tvg-name"])
        let name = nonEmpty(info.title) ?? tvgName ?? url.lastPathComponent
        let catchupDays = (attributes["catchup-days"] ?? attributes["timeshift"]).flatMap { Int($0) }

        return PlaylistEntry(
            name: name,
            url: url,
            tvgID: nonEmpty(attributes["tvg-id"]),
            tvgName: tvgName,
            logoURL: nonEmpty(attributes["tvg-logo"]).flatMap { URL(string: $0) },
            groupTitle: nonEmpty(attributes["group-title"]) ?? nonEmpty(group),
            catchupType: nonEmpty(attributes["catchup"] ?? attributes["catchup-type"]),
            catchupDays: catchupDays,
            catchupSource: nonEmpty(attributes["catchup-source"]),
            channelNumber: attributes["tvg-chno"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
