import ARJOCore
import SwiftUI

// MARK: Kontextmenüs

extension View {
    /// Favorit, Ausblenden, Umbenennen und Ordner für einen Sender.
    func channelMenu(_ channel: Channel, organization: OrganizationModel, multiview: MultiviewModel? = nil) -> some View {
        contextMenu {
            if let multiview {
                Button { multiview.present(adding: channel) } label: { Label("Im Multiview ansehen", systemImage: "rectangle.grid.2x2") }
            }
            Button {
                Task { await organization.toggleFavorite(channel) }
            } label: {
                Label(organization.isFavorite(channel) ? String(localized: "Aus Favoriten entfernen") : String(localized: "Zu Favoriten"),
                      systemImage: organization.isFavorite(channel) ? "star.slash" : "star")
            }
            Menu("Zu Ordner hinzufügen") {
                ForEach(organization.folders) { folder in
                    Button(folder.name) { Task { await organization.add(channel, to: folder) } }
                }
                Button("Ordner anlegen …") { organization.pendingEdit = .newFolder(adding: channel) }
            }
            Button("Sender umbenennen …") { organization.pendingEdit = .renameChannel(channel) }
            Button("Ausblenden", role: .destructive) { Task { await organization.setHidden(true, channel) } }
        }
    }

    /// Ausblenden und Umbenennen für eine Gruppe.
    func groupMenu(_ name: String, area: GroupArea, groups: [ChannelGroup], organization: OrganizationModel) -> some View {
        contextMenu {
            Button("Nach oben schieben") { Task { await organization.moveGroup(name, in: area, among: groups, by: -1) } }
            Button("Nach unten schieben") { Task { await organization.moveGroup(name, in: area, among: groups, by: 1) } }
            Button("Gruppe umbenennen …") { organization.pendingEdit = .renameGroup(area, name) }
            Button("Gruppe ausblenden", role: .destructive) {
                Task { await organization.setHidden(true, group: name, in: area) }
            }
        }
    }

    /// Zeigt das zentrale Eingabefenster für Umbenennen und neue Ordner.
    func organizationSheets(_ organization: OrganizationModel) -> some View {
        modifier(OrganizationSheets(organization: organization))
    }
}

private struct OrganizationSheets: ViewModifier {
    @Bindable var organization: OrganizationModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $organization.pendingEdit) { edit in
                NameEditSheet(title: title(edit), initial: initial(edit), allowsEmpty: allowsEmpty(edit)) { name in
                    Task { await apply(edit, name: name) }
                    organization.pendingEdit = nil
                } cancel: {
                    organization.pendingEdit = nil
                }
            }
            .alert(
                "Hinweis",
                isPresented: Binding(get: { organization.errorMessage != nil }, set: { if !$0 { organization.dismissError() } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(organization.errorMessage ?? "")
            }
    }

    private func title(_ edit: OrganizationModel.PendingEdit) -> String {
        switch edit {
        case .renameChannel, .renameGroup, .renameFolder: String(localized: "Umbenennen")
        case .newFolder: String(localized: "Neuer Ordner")
        }
    }

    private func initial(_ edit: OrganizationModel.PendingEdit) -> String {
        switch edit {
        case .renameChannel(let channel): organization.name(for: channel)
        case .renameGroup(let area, let name): organization.name(forGroup: name, in: area)
        case .newFolder: ""
        case .renameFolder(let folder): folder.name
        }
    }

    /// Bei Sendern und Gruppen setzt ein leerer Name den Originalnamen zurück.
    private func allowsEmpty(_ edit: OrganizationModel.PendingEdit) -> Bool {
        switch edit {
        case .renameChannel, .renameGroup: true
        case .newFolder, .renameFolder: false
        }
    }

    private func apply(_ edit: OrganizationModel.PendingEdit, name: String) async {
        switch edit {
        case .renameChannel(let channel): await organization.rename(channel, to: name)
        case .renameGroup(let area, let group): await organization.renameGroup(group, in: area, to: name)
        case .newFolder(let channel): await organization.createFolder(named: name, adding: channel)
        case .renameFolder(let folder): await organization.renameFolder(folder, to: name)
        }
    }
}

private struct NameEditSheet: View {
    let title: String
    let allowsEmpty: Bool
    let save: (String) -> Void
    let cancel: () -> Void
    @State private var name: String

    init(title: String, initial: String, allowsEmpty: Bool, save: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.title = title
        self.allowsEmpty = allowsEmpty
        self.save = save
        self.cancel = cancel
        _name = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    if allowsEmpty { Text("Leer lassen, um den Originalnamen wiederherzustellen.") }
                }
                Section {
                    Button("Sichern") { save(name) }
                        .disabled(!allowsEmpty && name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Abbrechen", role: .cancel, action: cancel)
                }
            }
            .navigationTitle(title)
        }
    }
}

// MARK: Verwaltung in den Einstellungen

struct OrganizationSettingsView: View {
    @Bindable var organization: OrganizationModel
    let groups: [GroupArea: [ChannelGroup]]

    var body: some View {
        Form {
            favoritesSection
            foldersSection
            ForEach(GroupArea.allCases, id: \.self) { area in
                if let list = groups[area], list.count > 1 { orderSection(area, list) }
            }
            hiddenSection
        }
        .navigationTitle("Favoriten & Ordner")
        .task { await organization.load() }
    }

    private var favoritesSection: some View {
        Section {
            if organization.favorites.isEmpty {
                Text("Noch keine Favoriten. Halte einen Sender gedrückt (Apple TV: lange auf die Mitte des Touch-Pads drücken) und wähle «Zu Favoriten».")
                    .foregroundStyle(.secondary)
            }
            ForEach(organization.favorites) { channel in
                HStack {
                    Text(organization.name(for: channel))
                    Spacer()
                    Menu("Aktionen") {
                        Button("Nach oben") { Task { await organization.moveFavorite(channel, by: -1) } }
                        Button("Nach unten") { Task { await organization.moveFavorite(channel, by: 1) } }
                        Button("Aus Favoriten entfernen", role: .destructive) { Task { await organization.toggleFavorite(channel) } }
                    }
                }
            }
        } header: {
            Text("Favoriten")
        }
    }

    private var foldersSection: some View {
        Section("Ordner") {
            ForEach(organization.folders) { folder in
                NavigationLink(folder.name) { FolderEditor(organization: organization, folderID: folder.id) }
            }
            Button("Ordner anlegen …") { organization.pendingEdit = .newFolder(adding: nil) }
        }
    }

    private func orderSection(_ area: GroupArea, _ list: [ChannelGroup]) -> some View {
        Section {
            ForEach(organization.ordered(list, in: area)) { group in
                HStack {
                    Text(organization.name(forGroup: group.name, in: area))
                    Spacer()
                    Menu("Aktionen") {
                        Button("Nach oben") { Task { await organization.moveGroup(group.name, in: area, among: list, by: -1) } }
                        Button("Nach unten") { Task { await organization.moveGroup(group.name, in: area, among: list, by: 1) } }
                    }
                }
            }
            if organization.hasCustomOrder(in: area, groups: list) {
                Button("Reihenfolge des Anbieters wiederherstellen") {
                    Task { await organization.resetGroupOrder(in: area, among: list) }
                }
            }
        } header: {
            Text("Reihenfolge: \(area.title)")
        }
    }

    private var hiddenSection: some View {
        Section {
            if organization.hiddenChannels.isEmpty && organization.hiddenGroupKeys.isEmpty {
                Text("Nichts ausgeblendet.").foregroundStyle(.secondary)
            }
            ForEach(organization.hiddenChannels) { channel in
                HStack {
                    Text(channel.name)
                    Spacer()
                    Button("Einblenden") { Task { await organization.setHidden(false, channel) } }
                }
            }
            ForEach(organization.hiddenGroupKeys, id: \.self) { key in
                HStack {
                    Text(Self.title(forGroupKey: key))
                    Spacer()
                    Button("Einblenden") { Task { await organization.unhide(key: key) } }
                }
            }
        } header: {
            Text("Ausgeblendet")
        }
    }

    private static func title(forGroupKey key: String) -> String {
        let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let area = GroupArea(rawValue: parts[1]) else { return key }
        return "\(area.title) · \(parts[2])"
    }
}

private struct FolderEditor: View {
    @Bindable var organization: OrganizationModel
    let folderID: UUID
    @Environment(\.dismiss) private var dismiss

    private var folder: ChannelFolder? { organization.folders.first { $0.id == folderID } }

    var body: some View {
        Form {
            if let folder {
                Section {
                    let channels = organization.folderChannels[folder.id] ?? []
                    if channels.isEmpty {
                        Text("Leer. Halte einen Sender gedrückt und wähle «Zu Ordner hinzufügen».").foregroundStyle(.secondary)
                    }
                    ForEach(channels) { channel in
                        HStack {
                            Text(organization.name(for: channel))
                            Spacer()
                            Menu("Aktionen") {
                                Button("Nach oben") { Task { await organization.move(channel, in: folder, by: -1) } }
                                Button("Nach unten") { Task { await organization.move(channel, in: folder, by: 1) } }
                                Button("Aus Ordner entfernen", role: .destructive) {
                                    Task { await organization.remove(channel, from: folder) }
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("Ordner umbenennen …") { organization.pendingEdit = .renameFolder(folder) }
                    Button("Ordner löschen", role: .destructive) {
                        Task {
                            await organization.deleteFolder(folder)
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(folder?.name ?? String(localized: "Ordner"))
    }
}
