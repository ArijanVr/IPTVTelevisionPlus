import ARJOCore
import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class AppModel {
    public enum Phase: Equatable {
        case launching
        case needsLogin
        case live(Profile)
        case failed(String)
    }

    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "profiles")

    public private(set) var phase: Phase = .launching
    public private(set) var profiles: [Profile] = []
    public private(set) var errorMessage: String?
    /// Adresse, die die App geöffnet hat (z. B. aus dem Top Shelf) und die noch bearbeitet werden muss.
    public private(set) var pendingDeepLink: URL?

    private let repository: any ProfileRepository
    private let activeProfile: any ActiveProfileStore
    private let credentialStore: any CredentialStore
    private let cleanups: [(UUID) async throws -> Void]
    private let localCleanups: [(UUID) async throws -> Void]
    private let prepareData: () async -> Void
    private let merging: ProfileMerging?

    /// - Parameters:
    ///   - cleanups: Löschen die Daten eines Profils (Katalog, EPG, Filme, Wiedergabestand …).
    ///   - localCleanups: Löschen nur die lokalen, neu ladbaren Daten (Katalog, EPG, Filme) eines zusammengeführten Profils.
    ///   - prepareData: Migration älterer Daten, läuft vor dem Lesen der Profile.
    ///   - merging: Führt Profile derselben Quelle zusammen, z. B. nach dem ersten iCloud-Abgleich.
    public init(
        profiles: any ProfileRepository,
        activeProfile: any ActiveProfileStore,
        credentialStore: any CredentialStore,
        cleanups: [(UUID) async throws -> Void],
        localCleanups: [(UUID) async throws -> Void] = [],
        prepareData: @escaping () async -> Void = {},
        merging: ProfileMerging? = nil
    ) {
        self.merging = merging
        repository = profiles
        self.activeProfile = activeProfile
        self.credentialStore = credentialStore
        self.cleanups = cleanups
        self.localCleanups = localCleanups
        self.prepareData = prepareData
    }

    /// Der Anmeldebildschirm lässt sich abbrechen, sobald es schon ein Profil gibt.
    public var canCancelLogin: Bool { !profiles.isEmpty }

    public func bootstrap() async {
        await prepareData()
        await reconcileProfiles()
        do {
            profiles = try await repository.profiles()
            if let active = profiles.first(where: { $0.id == activeProfile.activeProfileID }) ?? profiles.first {
                activate(active)
            } else {
                phase = .needsLogin
            }
        } catch {
            phase = .failed(String(localized: "Die gespeicherten Profile konnten nicht gelesen werden."))
        }
    }

    /// Liest die Profile neu ein, z. B. nach einer Änderung über iCloud auf einem anderen Gerät.
    public func refreshProfiles() async {
        guard phase != .launching else { return }
        await reconcileProfiles()
        do {
            profiles = try await repository.profiles()
        } catch {
            return
        }
        guard case .live(let current) = phase else { return }
        if let updated = profiles.first(where: { $0.id == current.id }) {
            // Gleiche Quelle, neuer Name oder Fingerabdruck: Sitzung bleibt bestehen.
            if updated != current { phase = .live(updated) }
        } else if let next = profiles.first(where: { $0.id == activeProfile.activeProfileID }) ?? profiles.first {
            activate(next)
        } else {
            phase = .needsLogin
        }
    }

    /// Ergänzt fehlende Fingerabdrücke (Profile älterer Versionen) und führt doppelte Quellen zusammen.
    /// Zugangsdaten bleiben in der Keychain dieses Geräts; sie wandern nur auf das bleibende Profil.
    private func reconcileProfiles() async {
        do {
            for profile in try await repository.profiles() where profile.sourceFingerprint == nil {
                guard let credentials = try? credentialStore.load(for: profile.id) else { continue }
                var updated = profile
                updated.sourceFingerprint = SourceFingerprint.make(for: credentials)
                try await repository.save(updated)
            }
            // Erst die Zugangsdaten auf das bleibende Profil kopieren, dann zusammenführen: Schlägt das Kopieren fehl,
            // bleibt alles unverändert und wird beim nächsten Start erneut versucht.
            guard let merging else { return }
            for (old, keep) in try await merging.planned() {
                // Der Fingerabdruck enthält kein Passwort: Lief auf diesem Gerät gerade das zusammengeführte Profil,
                // sind dessen Zugangsdaten die zuletzt benutzten und gehen vor.
                let preferOld = activeProfile.activeProfileID == old || (try? credentialStore.load(for: keep)) == nil
                // Ein Lesefehler bricht ab (statt als «keine Zugangsdaten» zu gelten), sonst gingen sie beim Zusammenführen verloren.
                if preferOld, let credentials = try credentialStore.load(for: old) {
                    try credentialStore.save(credentials, for: keep)
                }
            }
            for (old, keep) in try await merging.merge() {
                if activeProfile.activeProfileID == old { activeProfile.setActiveProfileID(keep) }
                try? credentialStore.delete(for: old)
                for cleanup in localCleanups { try? await cleanup(old) }
            }
        } catch {
            // Ohne Abgleich bleiben die Profile wie sie sind; beim nächsten Start wird es erneut versucht.
            Self.log.error("Profile nicht abgeglichen: \(error.localizedDescription)")
        }
    }

    public func signedIn(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        activate(profile)
    }

    public func switchTo(_ profile: Profile) {
        guard let current = profiles.first(where: { $0.id == profile.id }) else { return }
        activate(current)
    }

    public func beginAddingProfile() {
        phase = .needsLogin
    }

    public func cancelLogin() {
        guard let active = profiles.first(where: { $0.id == activeProfile.activeProfileID }) ?? profiles.first else { return }
        activate(active)
    }

    /// Entfernt Profil, Zugangsdaten und lokale Daten; wechselt bei Bedarf zu einem anderen Profil.
    public func signOut(_ profile: Profile) async {
        do {
            for cleanup in cleanups { try await cleanup(profile.id) }
            try credentialStore.delete(for: profile.id)
            try await repository.delete(id: profile.id)
        } catch {
            errorMessage = String(localized: "Abmelden ist fehlgeschlagen.")
            return
        }
        profiles.removeAll { $0.id == profile.id }
        if case .live(let current) = phase, current.id == profile.id {
            if let next = profiles.first {
                activate(next)
            } else {
                activeProfile.setActiveProfileID(nil)
                phase = .needsLogin
            }
        }
    }

    public func open(_ url: URL) {
        pendingDeepLink = url
    }

    public func consumeDeepLink() {
        pendingDeepLink = nil
    }

    public func dismissError() {
        errorMessage = nil
    }

    private func activate(_ profile: Profile) {
        activeProfile.setActiveProfileID(profile.id)
        phase = .live(profile)
    }
}

/// Zusammenführen doppelter Profile in zwei Schritten: `planned` ändert nichts und liefert alt → bleibend, damit die
/// Zugangsdaten vorher kopiert werden können; `merge` führt zusammen und löscht die alten Profile.
public struct ProfileMerging: Sendable {
    public let planned: @Sendable () async throws -> [UUID: UUID]
    public let merge: @Sendable () async throws -> [UUID: UUID]

    public init(planned: @escaping @Sendable () async throws -> [UUID: UUID], merge: @escaping @Sendable () async throws -> [UUID: UUID]) {
        self.planned = planned
        self.merge = merge
    }
}
