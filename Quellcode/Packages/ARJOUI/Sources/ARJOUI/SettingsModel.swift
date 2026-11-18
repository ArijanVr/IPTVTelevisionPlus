import ARJOCore
import Foundation
import Observation
import OSLog
import SwiftUI

/// Hält die Einstellungen im Speicher und schreibt Änderungen verzögert in den Speicher.
@MainActor
@Observable
public final class SettingsModel {
    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "settings")

    public var settings = AppSettings() {
        didSet { if settings != oldValue { scheduleSave() } }
    }
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repository: any SettingsRepository
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoading = false

    public init(repository: any SettingsRepository, debounce: Duration = .milliseconds(400)) {
        self.repository = repository
        self.debounce = debounce
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await repository.load()
        } catch {
            Self.log.error("Einstellungen nicht gelesen: \(error.localizedDescription)")
            errorMessage = String(localized: "Die Einstellungen konnten nicht gelesen werden. Es gelten die Standardwerte.")
        }
    }

    /// Schreibt ausstehende Änderungen sofort (z. B. vor dem Beenden).
    public func flush() async {
        saveTask?.cancel()
        await save(settings)
    }

    public func dismissError() {
        errorMessage = nil
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { [debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            await save(snapshot)
        }
    }

    private func save(_ snapshot: AppSettings) async {
        do {
            try await repository.save(snapshot)
        } catch {
            Self.log.error("Einstellungen nicht gespeichert: \(error.localizedDescription)")
            errorMessage = String(localized: "Die Einstellungen konnten nicht gespeichert werden.")
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct DisplayTimeZoneKey: EnvironmentKey {
    static let defaultValue = TimeZone.current
}

extension EnvironmentValues {
    /// Zeitzone für Uhrzeiten im Programmführer (Einstellung «Zeitzone»).
    var displayTimeZone: TimeZone {
        get { self[DisplayTimeZoneKey.self] }
        set { self[DisplayTimeZoneKey.self] = newValue }
    }
}
