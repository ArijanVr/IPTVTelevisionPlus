import Foundation
import Observation
import SwiftUI

/// Ein auf GitHub veröffentlichtes Release, das neuer ist als die laufende App.
public struct AppUpdate: Equatable, Sendable {
    public let version: String
    public let notes: String
    public let pageURL: URL
}

/// Fragt `releases/latest` der öffentlichen Release-Ablage ab und meldet, ob eine neuere Version bereitliegt.
/// Auf iPhone, iPad und Apple TV nur Hinweis (Apple erlaubt keine Selbstinstallation). Auf dem Mac übernimmt Sparkle.
@MainActor @Observable
public final class UpdateChecker {
    public enum State: Equatable {
        case idle, checking, upToDate
        case available(AppUpdate)
        case failed(String)
    }

    public static let releasesURL = URL(string: "https://api.github.com/repos/ArijanVr/IPTVTelevisionPlus/releases/latest")!
    private static let lastCheckKey = "ch.arjo.iptelevision.lastUpdateCheck"
    private static let interval: TimeInterval = 24 * 3600

    public private(set) var state: State = .idle
    private let currentVersion: String
    private let fetch: @Sendable (URL) async throws -> Data

    public init(
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        fetch: @escaping @Sendable (URL) async throws -> Data = UpdateChecker.fetchFromNetwork
    ) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    /// Prüft höchstens einmal pro Tag; für den Start der App.
    public func checkIfDue() async {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > Self.interval else { return }
        await check()
    }

    public func check() async {
        state = .checking
        do {
            let data = try await fetch(Self.releasesURL)
            let release = try JSONDecoder().decode(Release.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            if Self.isNewer(release.tagName, than: currentVersion) {
                state = .available(AppUpdate(version: Self.normalized(release.tagName), notes: release.body ?? "", pageURL: release.htmlURL))
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Vergleicht Versionen wie «v1.2.0» und «1.10» zahlenweise; fehlende Stellen zählen als 0.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        let a = components(remote), b = components(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func normalized(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    private nonisolated static func components(_ version: String) -> [Int] {
        normalized(version).split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: URL
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", body, htmlURL = "html_url" }
    }

    public nonisolated static func fetchFromNetwork(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

/// Zeile für die Einstellungen (iPhone, iPad, Apple TV): Stand der Prüfung und Link auf das Release.
struct UpdateRow: View {
    let checker: UpdateChecker

    var body: some View {
        Group {
            switch checker.state {
            case .idle, .upToDate:
                LabeledContent("Update", value: String(localized: "Aktuell"))
            case .checking:
                LabeledContent("Update", value: String(localized: "Suche …"))
            case .failed:
                LabeledContent("Update", value: String(localized: "Prüfung fehlgeschlagen"))
            case .available(let update):
                #if os(tvOS)
                LabeledContent("Update", value: String(localized: "Version \(update.version) verfügbar"))
                #else
                Link(destination: update.pageURL) {
                    LabeledContent("Update", value: String(localized: "Version \(update.version) laden"))
                }
                #endif
            }
        }
        Button("Nach Updates suchen") { Task { await checker.check() } }
            .disabled(checker.state == .checking)
    }
}
