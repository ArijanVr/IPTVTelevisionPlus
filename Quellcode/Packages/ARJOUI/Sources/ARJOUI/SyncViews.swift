import ARJOCore
import Observation
import SwiftUI

/// Abgleich ohne CloudKit: Version ohne iCloud-Berechtigung oder vom Nutzer ausgeschaltet.
@MainActor
@Observable
public final class StaticSyncMonitor: SyncMonitoring {
    public let status: SyncStatus

    public init(status: SyncStatus) {
        self.status = status
    }

    public func remoteChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    public func refresh() async {}
}

/// Schalter «Mit iCloud abgleichen» (pro Gerät, nicht synchronisiert). Wird beim Start der App gelesen.
public enum SyncPreference {
    public static let key = "ch.arjo.iptelevision.iCloudSyncEnabled"

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

extension SyncStatus {
    /// Kurzer Text für die Einstellungen.
    var title: String {
        switch self {
        case .unavailable: String(localized: "In dieser Version nicht verfügbar")
        case .disabled: String(localized: "Ausgeschaltet")
        case .checking: String(localized: "Wird geprüft …")
        case .noAccount: String(localized: "Nicht bei iCloud angemeldet")
        case .restricted: String(localized: "Durch Einschränkungen gesperrt")
        case .temporarilyUnavailable: String(localized: "iCloud vorübergehend nicht verfügbar")
        case .syncing: String(localized: "Wird abgeglichen …")
        case .upToDate: String(localized: "Aktuell")
        case .failed(let problem):
            switch problem {
            case .network: String(localized: "Keine Verbindung zu iCloud")
            case .quotaExceeded: String(localized: "iCloud-Speicher ist voll")
            case .rateLimited: String(localized: "iCloud ist ausgelastet")
            case .accountChanged: String(localized: "iCloud-Konto prüfen")
            case .other: String(localized: "Abgleich fehlgeschlagen")
            }
        }
    }

    /// Erklärung, was der Zustand für die Daten bedeutet; `nil`, wenn alles läuft.
    var explanation: String? {
        switch self {
        case .unavailable, .disabled:
            String(localized: "Wiedergabestand, Favoriten und Einstellungen bleiben auf diesem Gerät.")
        case .noAccount:
            String(localized: "Melde dich in den Systemeinstellungen bei iCloud an, um auf deinen Geräten weiterzuschauen. Bis dahin bleibt alles auf diesem Gerät.")
        case .restricted, .temporarilyUnavailable:
            String(localized: "Bis iCloud wieder verfügbar ist, wird alles auf diesem Gerät gespeichert und danach abgeglichen.")
        case .failed(.network):
            String(localized: "Änderungen werden gespeichert und abgeglichen, sobald wieder eine Verbindung besteht.")
        case .failed(.quotaExceeded):
            String(localized: "Gib iCloud-Speicher frei, damit neue Änderungen abgeglichen werden. Auf diesem Gerät bleibt alles gespeichert.")
        case .failed(.rateLimited):
            String(localized: "Der Abgleich wird später automatisch wiederholt.")
        case .failed(.accountChanged):
            String(localized: "Das iCloud-Konto wurde geändert oder ist abgemeldet. Daten verschiedener Konten werden nicht vermischt.")
        case .failed(.other(let message)):
            message
        case .checking, .syncing, .upToDate:
            nil
        }
    }
}

/// Einstellungen › iCloud: Zustand, Schalter und Verlauf löschen. Funktioniert auch ohne iCloud.
struct SyncSettingsSection: View {
    let sync: any SyncMonitoring
    let onClearHistory: () async -> Void
    @AppStorage(SyncPreference.key) private var syncEnabled = true
    @State private var confirmsClearing = false
    @State private var isClearing = false

    var body: some View {
        Section {
            LabeledContent("Status") {
                Text(sync.status.title)
            }
            if case .upToDate(let lastSync?) = sync.status {
                LabeledContent("Zuletzt abgeglichen") {
                    Text(lastSync, format: .dateTime.day().month().hour().minute())
                }
            }
            if sync.status != .unavailable {
                Toggle("Mit iCloud abgleichen", isOn: $syncEnabled)
            }
            Button(role: .destructive) {
                confirmsClearing = true
            } label: {
                if isClearing { ProgressView() } else { Text("Wiedergabeverlauf löschen") }
            }
            .disabled(isClearing)
            // Am Button statt an der Section: in einer Form erscheint der Dialog sonst nicht.
            .confirmationDialog("Wiedergabeverlauf löschen?", isPresented: $confirmsClearing, titleVisibility: .visible) {
                Button("Verlauf löschen", role: .destructive) {
                    Task {
                        isClearing = true
                        await onClearHistory()
                        isClearing = false
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Fortschritt, «Weiterschauen» und der zuletzt gesehene Sender dieser Quelle werden auf allen Geräten mit derselben iCloud entfernt.")
            }
        } header: {
            Text("iCloud")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if sync.status != .unavailable, sync.status != .disabled {
                    Text("Wiedergabestand, «Weiterschauen», zuletzt gesehener Sender, Favoriten, Ordner und Einstellungen liegen in deiner privaten iCloud. Zugangsdaten und PIN werden darüber nicht übertragen.")
                }
                if let explanation = sync.status.explanation { Text(explanation) }
                if syncEnabled != SyncPreference.launchValue {
                    Text("Die Änderung wirkt nach dem nächsten Start der App.")
                }
            }
        }
        .task { await sync.refresh() }
    }
}

extension SyncPreference {
    /// Wert beim Start dieser Sitzung (der Speicher wird nur beim Start konfiguriert).
    @MainActor public static let launchValue = isEnabled
}
