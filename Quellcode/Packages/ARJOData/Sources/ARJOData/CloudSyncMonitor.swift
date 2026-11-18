#if canImport(CloudKit)
import ARJOCore
import CloudKit
import CoreData
import Foundation
import Observation
import OSLog

/// Beobachtet den CloudKit-Abgleich des Nutzerdaten-Speichers (SwiftData nutzt dafür `NSPersistentCloudKitContainer`).
///
/// Den eigentlichen Abgleich, Wiederholungen mit Backoff, Push-Benachrichtigungen und das Verhalten bei
/// Kontowechseln übernimmt das System. Diese Klasse meldet nur den Zustand für die Oberfläche und sagt Bescheid,
/// wenn Änderungen anderer Geräte importiert wurden.
///
/// Nur erzeugen, wenn die App die iCloud-Berechtigung hat (Kompilierflag `ICLOUD_SYNC`): `CKContainer` beendet
/// die App ohne Berechtigung.
@MainActor
@Observable
public final class CloudSyncMonitor: SyncMonitoring {
    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "sync")

    public private(set) var status: SyncStatus = .checking

    @ObservationIgnored private let container: CKContainer
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private var accountAvailable = false
    @ObservationIgnored private var runningEvents = Set<UUID>()

    public init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let snapshot = EventSnapshot(event)
            MainActor.assumeIsolated { self?.handle(snapshot) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Self.log.notice("iCloud-Konto geändert")
                Task {
                    await self.refresh()
                    self.notifyListeners()
                }
            }
        })
        Task { [weak self] in await self?.refresh() }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        listeners.values.forEach { $0.finish() }
    }

    public func remoteChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.listeners[id] = nil }
        }
        return stream
    }

    public func refresh() async {
        do {
            let account = try await container.accountStatus()
            accountAvailable = account == .available
            switch account {
            case .available:
                if case .failed = status { break }
                status = runningEvents.isEmpty ? .upToDate(lastSync: lastSync) : .syncing
            case .noAccount: status = .noAccount
            case .restricted: status = .restricted
            case .temporarilyUnavailable: status = .temporarilyUnavailable
            case .couldNotDetermine: status = .failed(.other(String(localized: "Der iCloud-Status ist unbekannt.")))
            @unknown default: status = .failed(.other(String(localized: "Der iCloud-Status ist unbekannt.")))
            }
        } catch {
            accountAvailable = false
            status = .failed(Self.problem(for: error))
        }
    }

    private func handle(_ event: EventSnapshot) {
        guard event.type != .setup || event.endDate != nil else { return }
        if event.endDate == nil {
            runningEvents.insert(event.id)
            if accountAvailable || status == .checking { status = .syncing }
            return
        }
        runningEvents.remove(event.id)
        if let error = event.error, !event.succeeded {
            Self.log.error("Abgleich fehlgeschlagen: \(error.localizedDescription)")
            status = .failed(Self.problem(for: error))
            return
        }
        lastSync = event.endDate
        if runningEvents.isEmpty { status = .upToDate(lastSync: lastSync) }
        if event.type == .import { notifyListeners() }
    }

    private func notifyListeners() {
        listeners.values.forEach { $0.yield() }
    }

    static func problem(for error: Error) -> SyncProblem {
        guard let ckError = error as? CKError else {
            return .other(error.localizedDescription)
        }
        if ckError.code == .partialFailure, let partial = ckError.partialErrorsByItemID?.values.first {
            return problem(for: partial)
        }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serverResponseLost: return .network
        case .quotaExceeded: return .quotaExceeded
        case .requestRateLimited, .zoneBusy, .serviceUnavailable: return .rateLimited
        case .notAuthenticated, .accountTemporarilyUnavailable: return .accountChanged
        default: return .other(ckError.localizedDescription)
        }
    }
}

/// Kopie der benötigten Werte, damit das nicht-sendable Ereignisobjekt den Thread nicht wechseln muss.
private struct EventSnapshot: @unchecked Sendable {
    let id: UUID
    let type: NSPersistentCloudKitContainer.EventType
    let endDate: Date?
    let succeeded: Bool
    let error: Error?

    init(_ event: NSPersistentCloudKitContainer.Event) {
        id = event.identifier
        type = event.type
        endDate = event.endDate
        succeeded = event.succeeded
        error = event.error
    }
}
#endif
