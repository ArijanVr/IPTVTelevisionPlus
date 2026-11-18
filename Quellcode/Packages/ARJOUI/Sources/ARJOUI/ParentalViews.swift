import ARJOCore
import SwiftUI

/// Eingabefeld für die PIN, auch zum Festlegen (mit Wiederholung).
struct PINPromptView: View {
    enum Mode {
        case unlock
        case create
    }

    let parental: ParentalControl
    let mode: Mode
    let title: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var pin = ""
    @State private var repeatedPIN = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("PIN", text: $pin)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    if mode == .create {
                        SecureField("PIN wiederholen", text: $repeatedPIN)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                } footer: {
                    if let message = localError ?? parental.errorMessage {
                        Text(message).foregroundStyle(.red)
                    } else if mode == .create {
                        Text("4 bis 6 Ziffern.")
                    }
                }
                Section {
                    Button(LocalizedStringKey(mode == .create ? "PIN festlegen" : "Entsperren"), action: submit)
                        .disabled(pin.isEmpty || parental.lockoutRemaining != nil)
                    Button("Abbrechen", role: .cancel, action: onCancel)
                }
            }
            .navigationTitle(title)
        }
        .onAppear { parental.dismissError() }
    }

    private func submit() {
        localError = nil
        switch mode {
        case .unlock:
            if parental.unlock(pin: pin) { onSuccess() } else { pin = "" }
        case .create:
            guard pin == repeatedPIN else {
                localError = String(localized: "Die PINs stimmen nicht überein.")
                return
            }
            if parental.setPIN(pin) { onSuccess() }
        }
    }
}

/// Platzhalter für eine gesperrte Gruppe.
struct LockedGroupRow: View {
    let name: String
    let unlock: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
            Text(name).font(.arjo(.headline))
            Text("Gesperrt").foregroundStyle(.secondary)
            Spacer()
            Button("Entsperren", action: unlock)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 8)
    }
}

/// Kindersicherung in den Einstellungen: PIN verwalten und Gruppen sperren.
struct ParentalSettingsView: View {
    let parental: ParentalControl
    let session: ProfileSession

    @State private var sheet: PINSheetKind?

    /// Ohne PIN darf jeder einrichten; mit PIN nur, wer sie kennt.
    private var isAuthorized: Bool { parental.isUnlocked }

    var body: some View {
        Form {
            if !parental.hasPIN {
                Section {
                    Button("PIN festlegen") { sheet = .create }
                } footer: {
                    Text("Mit einer PIN kannst du ausgewählte Kategorien für Kinder sperren.")
                }
            } else if !isAuthorized {
                Section {
                    Button("PIN eingeben") { parental.requestUnlock() }
                } footer: {
                    Text("Die Kindersicherung ist durch eine PIN geschützt.")
                }
            } else {
                Section {
                    Button("PIN ändern") { sheet = .change }
                    Button("PIN entfernen", role: .destructive) { sheet = .remove }
                }
                ForEach(GroupArea.allCases, id: \.self) { area in
                    Section(area.title) {
                        let groups = groups(for: area)
                        if groups.isEmpty {
                            Text("Keine Gruppen geladen.").foregroundStyle(.secondary)
                        }
                        ForEach(groups) { group in
                            Toggle(group.name, isOn: Binding(
                                get: { parental.isMarkedLocked(area, group.name) },
                                set: { parental.setMarkedLocked($0, area: area, group: group.name) }
                            ))
                        }
                    }
                }
            }
        }
        .navigationTitle("Kindersicherung")
        .task {
            await session.movies.load()
            await session.series.load()
        }
        .onAppear { if parental.hasPIN, !parental.isUnlocked { parental.requestUnlock() } }
        .sheet(item: $sheet) { sheet in
            PINManageSheet(parental: parental, kind: sheet) { self.sheet = nil }
        }
    }

    private func groups(for area: GroupArea) -> [ChannelGroup] {
        switch area {
        case .live: session.live.groups
        case .movie: session.movies.groups
        case .series: session.series.groups
        }
    }
}

/// Festlegen, ändern und entfernen der PIN.
private struct PINManageSheet: View {
    let parental: ParentalControl
    let kind: PINSheetKind
    let close: () -> Void

    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if kind != .create {
                        field("Aktuelle PIN", text: $current)
                    }
                    if kind != .remove {
                        field(LocalizedStringKey(kind == .create ? "PIN" : "Neue PIN"), text: $new)
                        field("PIN wiederholen", text: $repeated)
                    }
                } footer: {
                    if let message = localError ?? parental.errorMessage {
                        Text(message).foregroundStyle(.red)
                    } else if kind != .remove {
                        Text("4 bis 6 Ziffern.")
                    }
                }
                Section {
                    Button(kind.buttonTitle, role: kind == .remove ? .destructive : nil, action: submit)
                        .disabled(parental.lockoutRemaining != nil)
                    Button("Abbrechen", role: .cancel, action: close)
                }
            }
            .navigationTitle(kind.title)
        }
        .onAppear { parental.dismissError() }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
    }

    private func submit() {
        localError = nil
        if kind != .remove, new != repeated {
            localError = String(localized: "Die PINs stimmen nicht überein.")
            return
        }
        let succeeded: Bool
        switch kind {
        case .create: succeeded = parental.setPIN(new)
        case .change: succeeded = parental.changePIN(current: current, new: new)
        case .remove: succeeded = parental.removePIN(current: current)
        }
        if succeeded { close() }
    }
}

enum PINSheetKind: Identifiable {
    case create, change, remove

    var id: Self { self }

    var title: String {
        switch self {
        case .create: String(localized: "PIN festlegen")
        case .change: String(localized: "PIN ändern")
        case .remove: String(localized: "PIN entfernen")
        }
    }

    var buttonTitle: String {
        switch self {
        case .create: String(localized: "PIN festlegen")
        case .change: String(localized: "PIN ändern")
        case .remove: String(localized: "PIN entfernen")
        }
    }
}
