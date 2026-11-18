import ARJOCore
import Foundation
import Observation
import OSLog

/// Kindersicherung eines Profils: Gruppen lassen sich mit einer PIN sperren.
/// Nach richtiger PIN sind alle gesperrten Gruppen für `unlockDuration` frei.
@MainActor
@Observable
public final class ParentalControl {
    public static let unlockDuration: TimeInterval = 10 * 60
    public static let maxFailedAttempts = 5
    public static let lockoutDuration: TimeInterval = 60
    public static let pinLengths = 4...6

    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "parental")

    public private(set) var hasPIN = false
    public private(set) var unlockedUntil: Date?
    public private(set) var lockoutUntil: Date?
    public private(set) var errorMessage: String?
    /// Wird von Ansichten gesetzt, die eine Entsperrung brauchen; ein zentrales PIN-Fenster reagiert darauf.
    public var isPromptingPIN = false

    private let profileID: UUID
    private let settings: SettingsModel
    private let pinStore: any PINStore
    private let clock: () -> Date
    private var failedAttempts = 0
    private var relockTask: Task<Void, Never>?

    public init(profileID: UUID, settings: SettingsModel, pinStore: any PINStore, clock: @escaping () -> Date = { Date() }) {
        self.profileID = profileID
        self.settings = settings
        self.pinStore = pinStore
        self.clock = clock
        refreshPINState()
    }

    public var isUnlocked: Bool {
        unlockedUntil.map { $0 > clock() } ?? false
    }

    public var lockoutRemaining: TimeInterval? {
        lockoutUntil.map { $0.timeIntervalSince(clock()) }.flatMap { $0 > 0 ? $0 : nil }
    }

    public static func isValidPIN(_ pin: String) -> Bool {
        pinLengths.contains(pin.count) && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: Prüfen

    /// `true`, wenn der Inhalt gerade verborgen werden muss.
    public func isLocked(_ area: GroupArea, _ group: String?) -> Bool {
        guard hasPIN, !isUnlocked, let group else { return false }
        return markedKeys.contains(GroupKey.make(area, group))
    }

    /// Ob die Gruppe in den Einstellungen als gesperrt markiert ist (unabhängig von Entsperrung und PIN).
    public func isMarkedLocked(_ area: GroupArea, _ group: String) -> Bool {
        markedKeys.contains(GroupKey.make(area, group))
    }

    public func setMarkedLocked(_ locked: Bool, area: GroupArea, group: String) {
        var keys = Set(markedKeys)
        let key = GroupKey.make(area, group)
        if locked { keys.insert(key) } else { keys.remove(key) }
        settings.settings.lockedGroups[profileID.uuidString] = keys.sorted()
    }

    // MARK: Entsperren

    /// Prüft die PIN; zu viele Fehlversuche sperren die Eingabe kurz.
    @discardableResult
    public func verify(_ pin: String) -> Bool {
        if lockoutRemaining != nil {
            errorMessage = String(localized: "Zu viele Versuche. Bitte warte kurz.")
            return false
        }
        do {
            if try pinStore.verify(pin) {
                failedAttempts = 0
                errorMessage = nil
                return true
            }
        } catch {
            Self.log.error("PIN nicht prüfbar: \(error.localizedDescription)")
            errorMessage = String(localized: "Die PIN konnte nicht geprüft werden.")
            return false
        }
        failedAttempts += 1
        if failedAttempts >= Self.maxFailedAttempts {
            failedAttempts = 0
            lockoutUntil = clock().addingTimeInterval(Self.lockoutDuration)
            errorMessage = String(localized: "Zu viele Versuche. Bitte warte kurz.")
        } else {
            errorMessage = String(localized: "Falsche PIN.")
        }
        return false
    }

    @discardableResult
    public func unlock(pin: String) -> Bool {
        guard verify(pin) else { return false }
        unlockedUntil = clock().addingTimeInterval(Self.unlockDuration)
        isPromptingPIN = false
        relockTask?.cancel()
        relockTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Self.unlockDuration)) } catch { return }
            self?.lockNow()
        }
        return true
    }

    public func lockNow() {
        relockTask?.cancel()
        unlockedUntil = nil
    }

    public func requestUnlock() {
        isPromptingPIN = true
    }

    // MARK: PIN verwalten

    public func setPIN(_ pin: String) -> Bool {
        guard Self.isValidPIN(pin) else {
            errorMessage = String(localized: "Die PIN muss 4 bis 6 Ziffern haben.")
            return false
        }
        return perform(String(localized: "Die PIN konnte nicht gespeichert werden.")) { try pinStore.setPIN(pin) }
    }

    public func changePIN(current: String, new: String) -> Bool {
        guard verify(current) else { return false }
        return setPIN(new)
    }

    public func removePIN(current: String) -> Bool {
        guard verify(current) else { return false }
        return perform(String(localized: "Die PIN konnte nicht entfernt werden.")) {
            try pinStore.removePIN()
            lockNow()
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    private var markedKeys: [String] { settings.settings.lockedGroups[profileID.uuidString] ?? [] }

    private func perform(_ failure: String, _ work: () throws -> Void) -> Bool {
        do {
            try work()
            errorMessage = nil
            refreshPINState()
            return true
        } catch {
            Self.log.error("\(failure) \(error.localizedDescription)")
            errorMessage = failure
            return false
        }
    }

    private func refreshPINState() {
        do {
            hasPIN = try pinStore.hasPIN
        } catch {
            Self.log.error("PIN-Status unbekannt: \(error.localizedDescription)")
            // Im Zweifel gesperrt lassen.
            hasPIN = true
        }
    }
}
