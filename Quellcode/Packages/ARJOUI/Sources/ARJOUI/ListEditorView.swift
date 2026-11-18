import ARJOCore
import SwiftUI

/// Öffnet den Listen-Editor auf einer bestimmten Seite (gesetzt von `MainTabView`).
struct ListEditorOpener {
    var open: @MainActor (ListEditorView.Page) -> Void = { _ in }

    @MainActor func callAsFunction(_ page: ListEditorView.Page) { open(page) }
}

extension EnvironmentValues {
    @Entry var openListEditor = ListEditorOpener()
}

/// «Meine Listen»: Kategorien ein-/ausblenden und ordnen, Sender ausblenden, umbenennen und als Favorit markieren,
/// Aufbau der Startseite und Darstellung der Kacheln. Alles wirkt sofort und wird pro Profil bzw. in den Einstellungen gespeichert.
struct ListEditorView: View {
    enum Page: String, CaseIterable, Identifiable {
        case categories, channels, home
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .categories: "Kategorien"
            case .channels: "Sender"
            case .home: "Jetzt"
            }
        }
    }

    @Bindable var settings: SettingsModel
    let session: ProfileSession
    @State var page: Page
    var onClose: (() -> Void)?

    var body: some View {
        // Als eigenes Fenster mit Navigation; in den Einstellungen nur der Inhalt (die Navigation gibt es dort schon).
        if onClose != nil {
            NavigationStack { content }
                #if os(macOS)
                .fitsInMainWindow(width: 820, height: 760, chrome: 72)
                #endif
                .organizationSheets(session.organization)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("Bereich", selection: $page) {
                ForEach(Page.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            switch page {
            case .categories: CategoryEditor(session: session)
            case .channels: ChannelEditor(session: session)
            case .home: HomeLayoutEditor(settings: settings)
            }
        }
        .navigationTitle("Meine Listen")
        #if !os(tvOS)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig", action: onClose) }
            }
        }
        #endif
    }
}

// MARK: - Kategorien

private struct CategoryEditor: View {
    let session: ProfileSession
    @State private var area: GroupArea = .live

    private var organization: OrganizationModel { session.organization }

    private var groups: [ChannelGroup] {
        switch area {
        case .live: session.live.groups
        case .movie: session.movies.groups
        case .series: session.series.groups
        }
    }

    var body: some View {
        let ordered = organization.ordered(groups, in: area)
        let hiddenCount = ordered.filter { organization.isHidden(group: $0.name, in: area) }.count
        List {
            Section {
                Picker("Bereich", selection: $area) {
                    ForEach(GroupArea.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                if ordered.isEmpty {
                    Text("Noch keine Kategorien geladen.").foregroundStyle(.secondary)
                }
                ForEach(ordered) { group in
                    row(group, among: ordered)
                }
                .onMove { source, destination in
                    Task { await organization.moveGroups(in: area, among: groups, fromOffsets: source, toOffset: destination) }
                }
            } header: {
                Text("\(ordered.count - hiddenCount) von \(ordered.count) sichtbar")
            } footer: {
                Text(Self.hint)
            }
            if organization.hasCustomOrder(in: area, groups: groups) {
                Section {
                    Button("Reihenfolge des Anbieters wiederherstellen") {
                        Task { await organization.resetGroupOrder(in: area, among: groups) }
                    }
                }
            }
        }
        .editorListStyle()
    }

    private func row(_ group: ChannelGroup, among ordered: [ChannelGroup]) -> some View {
        let hidden = organization.isHidden(group: group.name, in: area)
        return HStack(spacing: 14) {
            VisibilityToggle(isVisible: !hidden) {
                Task { await organization.setHidden(!hidden, group: group.name, in: area) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(organization.name(forGroup: group.name, in: area))
                    .font(.arjo(.bodyMedium))
                    .foregroundStyle(hidden ? .secondary : .primary)
                if organization.name(forGroup: group.name, in: area) != group.name {
                    Text(group.name).font(.arjo(.small)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(group.channelCount)").font(.arjo(.small)).foregroundStyle(.secondary).monospacedDigit()
            Menu {
                Button("Umbenennen …") { organization.pendingEdit = .renameGroup(area, group.name) }
                Button("Nach oben") { Task { await organization.moveGroup(group.name, in: area, among: groups, by: -1) } }
                    .disabled(ordered.first == group)
                Button("Nach unten") { Task { await organization.moveGroup(group.name, in: area, among: groups, by: 1) } }
                    .disabled(ordered.last == group)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("Aktionen")
        }
        .padding(.vertical, 4)
        .opacity(hidden ? 0.6 : 1)
    }

    #if os(tvOS)
    private static let hint: LocalizedStringKey = "Auge: ein- oder ausblenden. Reihenfolge über das Menü «…»."
    #else
    private static let hint: LocalizedStringKey = "Auge: ein- oder ausblenden. Zum Ordnen eine Zeile ziehen."
    #endif
}

// MARK: - Sender

private struct ChannelEditor: View {
    private enum Source: Hashable {
        case favorites
        case group(ChannelGroup)
    }

    let session: ProfileSession
    @State private var source: Source = .favorites
    @State private var channels: [Channel] = []
    @State private var failed = false

    private var organization: OrganizationModel { session.organization }
    private var groups: [ChannelGroup] { organization.ordered(session.live.groups, in: .live) }

    var body: some View {
        List {
            Section {
                Picker("Liste", selection: $source) {
                    Text("Favoriten").tag(Source.favorites)
                    ForEach(groups) { group in
                        Text(verbatim: organization.name(forGroup: group.name, in: .live)).tag(Source.group(group))
                    }
                }
            }
            Section {
                if failed {
                    Text("Die Sender konnten nicht geladen werden.").foregroundStyle(.secondary)
                } else if shown.isEmpty {
                    Text(source == .favorites
                         ? "Noch keine Favoriten. Markiere Sender mit dem Stern."
                         : "Keine Sender in dieser Kategorie.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { row($0) }
                    .onMove { from, to in
                        Task {
                            if source == .favorites {
                                await organization.moveFavorites(fromOffsets: from, toOffset: to)
                            } else {
                                await organization.moveChannels(among: channels, fromOffsets: from, toOffset: to)
                            }
                        }
                    }
            } header: {
                let hidden = shown.filter(organization.isHidden).count
                Text("\(shown.count - hidden) von \(shown.count) sichtbar")
            } footer: {
                Text("Auge: Sender ein- oder ausblenden. Stern: Favorit. Zum Ordnen eine Zeile ziehen – oder in den Reihen eine Kachel auf eine andere ziehen.")
            }
            if case .group = source, shown.contains(where: organization.isHidden) {
                Section {
                    Button("Alle Sender dieser Kategorie einblenden") {
                        Task { for channel in shown where organization.isHidden(channel) { await organization.setHidden(false, channel) } }
                    }
                }
            }
        }
        .editorListStyle()
        .task(id: source) { await load() }
    }

    private var shown: [Channel] {
        source == .favorites ? organization.favorites : organization.ordered(channels)
    }

    private func load() async {
        failed = false
        guard case .group(let group) = source else { return }
        do {
            channels = try await session.live.channels(in: group)
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }

    private func row(_ channel: Channel) -> some View {
        let hidden = organization.isHidden(channel)
        let favorite = organization.isFavorite(channel)
        let name = organization.name(for: channel)
        return HStack(spacing: 14) {
            VisibilityToggle(isVisible: !hidden) {
                Task { await organization.setHidden(!hidden, channel) }
            }
            ChannelArtwork(logoURL: channel.logoURL, name: name, cornerRadius: 6)
                .frame(width: Self.logoSize.width, height: Self.logoSize.height)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.arjo(.bodyMedium)).lineLimit(1)
                if name != channel.name {
                    Text(channel.name).font(.arjo(.small)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button {
                Task { await organization.toggleFavorite(channel) }
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? Theme.glut : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(favorite ? "Aus Favoriten entfernen" : "Zu Favoriten")
            Button {
                organization.pendingEdit = .renameChannel(channel)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Sender umbenennen")
        }
        .padding(.vertical, 2)
        .opacity(hidden ? 0.55 : 1)
    }

    #if os(tvOS)
    private static let logoSize = CGSize(width: 112, height: 63)
    #else
    private static let logoSize = CGSize(width: 64, height: 36)
    #endif
}

// MARK: - Startseite und Kacheln

private struct HomeLayoutEditor: View {
    @Bindable var settings: SettingsModel

    private var order: [HomeSection] { HomeSection.normalized(settings.settings.homeOrder) }

    var body: some View {
        List {
            Section {
                tilePreview
                Toggle("Sendernamen unter den Kacheln", isOn: $settings.settings.showsChannelNames)
                Picker("Kachelgrösse", selection: $settings.settings.tileSize) {
                    ForEach(TileSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Senderkacheln")
            } footer: {
                Text("Ohne Namen erscheint der Name nur, wenn eine Kachel ausgewählt ist.")
            }
            Section {
                ForEach(order) { section in
                    let visible = !settings.settings.hiddenHomeSections.contains(section)
                    HStack(spacing: 14) {
                        VisibilityToggle(isVisible: visible) { toggle(section) }
                        Image(systemName: section.symbol).frame(width: 28).foregroundStyle(.secondary)
                        Text(section.title).font(.arjo(.bodyMedium)).foregroundStyle(visible ? .primary : .secondary)
                        Spacer()
                        #if os(tvOS)
                        Menu {
                            Button("Nach oben") { move(section, by: -1) }.disabled(order.first == section)
                            Button("Nach unten") { move(section, by: 1) }.disabled(order.last == section)
                        } label: { Image(systemName: "ellipsis.circle") }
                        #endif
                    }
                    .padding(.vertical, 4)
                    .opacity(visible ? 1 : 0.6)
                }
                .onMove { source, destination in
                    var list = order
                    list.move(fromOffsets: source, toOffset: destination)
                    settings.settings.homeOrder = list
                }
            } header: {
                Text("Reihen der Startseite")
            } footer: {
                #if os(tvOS)
                Text("Auge: Reihe ein- oder ausblenden. Reihenfolge über das Menü «…».")
                #else
                Text("Auge: Reihe ein- oder ausblenden. Zum Ordnen eine Zeile ziehen.")
                #endif
            }
            if settings.settings.homeOrder != HomeSection.allCases || !settings.settings.hiddenHomeSections.isEmpty {
                Section {
                    Button("Standard-Aufbau wiederherstellen") {
                        settings.settings.homeOrder = HomeSection.allCases
                        settings.settings.hiddenHomeSections = []
                    }
                }
            }
        }
        .editorListStyle()
    }

    /// Vorschau mit Beispiel-Logos in der gewählten Grösse.
    private var tilePreview: some View {
        let style = ChannelTileStyle(showsNames: settings.settings.showsChannelNames, size: settings.settings.tileSize)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(["SRF 1", "Das Erste", "Arte"], id: \.self) { name in
                    VStack(alignment: .leading, spacing: 8) {
                        ChannelArtwork(logoURL: nil, name: name, progress: 0.4)
                            .frame(width: style.artworkSize.width, height: style.artworkSize.height)
                        if style.showsNames {
                            Text(verbatim: name).font(.arjo(.bodyMedium))
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .animation(.smooth, value: style)
        }
        .accessibilityHidden(true)
    }

    private func toggle(_ section: HomeSection) {
        if settings.settings.hiddenHomeSections.contains(section) {
            settings.settings.hiddenHomeSections.remove(section)
        } else {
            settings.settings.hiddenHomeSections.insert(section)
        }
    }

    private func move(_ section: HomeSection, by offset: Int) {
        var list = order
        guard let index = list.firstIndex(of: section), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        settings.settings.homeOrder = list
    }
}

// MARK: - Bausteine

/// Auge zum Ein- und Ausblenden.
private struct VisibilityToggle: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                .foregroundStyle(isVisible ? Theme.text : Color.secondary)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isVisible ? "Ausblenden" : "Einblenden")
    }
}

private extension View {
    /// Ziehen zum Ordnen: auf iPhone/iPad dauerhaft im Bearbeiten-Modus, auf dem Mac ohne.
    @ViewBuilder
    func editorListStyle() -> some View {
        #if os(iOS)
        self.environment(\.editMode, .constant(.active))
        #elseif os(macOS)
        self.listStyle(.inset)
        #else
        self
        #endif
    }
}
