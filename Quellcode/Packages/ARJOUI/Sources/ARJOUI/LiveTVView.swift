import ARJOCore
import SwiftUI

public struct LiveTVView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case channels = "Sender"
        case categories = "Kategorien"
        case guide = "Programmführer"
        var id: Self { self }
    }

    @Bindable private var model: LiveTVViewModel
    @Environment(ParentalControl.self) private var parental
    @Environment(OrganizationModel.self) private var organization
    @Environment(MultiviewModel.self) private var multiview
    @Environment(\.openListEditor) private var openListEditor
    @State private var guide: GuideViewModel
    @State private var mode: Mode = .channels
    @State private var visitedGuide = false
    private let onSignOut: () async -> Void

    public init(
        model: LiveTVViewModel,
        parental: ParentalControl,
        organization: OrganizationModel,
        onSignOut: @escaping () async -> Void
    ) {
        self.model = model
        _guide = State(initialValue: GuideViewModel(
            live: model,
            isAllowed: { [parental, organization] in
                !parental.isLocked(.live, $0.name) && !organization.isHidden(group: $0.name, in: .live)
            },
            isVisible: { [organization] in !organization.isHidden($0) }
        ))
        self.onSignOut = onSignOut
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Live")
                .navigationDestination(for: ChannelGroup.self) { CategoryDetailView(group: $0, model: model) }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Ansicht", selection: $mode) {
                            ForEach(Mode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 500)
                    }
                    ToolbarItem {
                        Button { openListEditor(mode == .categories ? .categories : .channels) } label: { Image(systemName: "slider.horizontal.3") }
                            .accessibilityLabel("Listen bearbeiten")
                    }
                    ToolbarItem {
                        Button { multiview.present() } label: { Image(systemName: "rectangle.grid.2x2") }
                            .accessibilityLabel("Multiview")
                    }
                    ToolbarItem {
                        PlaylistStatusDot(health: model.health)
                    }
                    ToolbarItem {
                        Button { Task { await model.refreshAll() } } label: {
                            if model.isRefreshing || model.epg.status == .updating {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(model.isRefreshing || model.epg.status == .updating)
                        .accessibilityLabel("Playlist aktualisieren")
                    }
                    ToolbarItem {
                        Menu {
                            Button("Programmführer aktualisieren") { Task { await model.epg.refresh() } }
                                .disabled(model.epg.status == .updating)
                            Button("Abmelden", role: .destructive) { Task { await onSignOut() } }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
        .task { await model.load() }
        .alert(
            "Aktualisieren fehlgeschlagen",
            isPresented: Binding(get: { model.refreshError != nil }, set: { if !$0 { model.refreshError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.refreshError ?? "")
        }
        .alert(
            "Programmführer nicht verfügbar",
            isPresented: Binding(
                get: { if case .failed = model.epg.status { true } else { false } },
                set: { if !$0 { model.epg.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(let message) = model.epg.status { Text(message) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 20) {
                ProgressView()
                Text("Senderliste wird geladen …").foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(spacing: 24) {
                Text(message).multilineTextAlignment(.center)
                Button("Erneut versuchen") { Task { await model.load() } }
            }
            .padding(40)
        case .ready:
            // Alle Ansichten bleiben bestehen und blenden nur ineinander über: kein Neuaufbau, kein Nachladen beim Wechsel.
            ZStack {
                modeLayer(.channels) { channelRows }
                modeLayer(.categories) { CategoryGrid(groups: organization.visible(model.groups, in: .live)) }
                if visitedGuide || mode == .guide {
                    modeLayer(.guide) { GuideView(live: model, guide: guide) }
                }
            }
            .animation(.smooth(duration: 0.25), value: mode)
            .onChange(of: mode) { _, new in if new == .guide { visitedGuide = true } }
        }
    }

    private func modeLayer<Content: View>(_ layer: Mode, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(mode == layer ? 1 : 0)
            .disabled(mode != layer)
            .accessibilityHidden(mode != layer)
    }

    private var channelRows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                if let last = model.lastChannel, !parental.isLocked(.live, last.groupName) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Zuletzt gesehen").font(.arjo(.headline)).padding(.horizontal, 48)
                        ChannelTile(channel: last, nowNext: model.epg.nowNext(for: last)) { model.play(last, in: [last]) }
                            .padding(.horizontal, 48)
                            .padding(.vertical, 16)
                    }
                }
                if !organization.favorites.isEmpty {
                    channelRow(title: "Favoriten", channels: visibleUnlocked(organization.favorites)) { dragged, target in
                        Task { await organization.moveFavorite(dragged, to: target) }
                    }
                }
                ForEach(organization.folders) { folder in
                    let channels = visibleUnlocked(organization.folderChannels[folder.id] ?? [])
                    if !channels.isEmpty {
                        channelRow(title: folder.name, channels: channels) { dragged, target in
                            Task { await organization.move(dragged, to: target, in: folder) }
                        }
                    }
                }
                ForEach(organization.visible(model.groups, in: .live)) { group in
                    GroupRow(group: group, model: model)
                }
            }
            .padding(.vertical, 24)
        }
        .focusBackdrop()
    }
}

extension LiveTVView {
    private func visibleUnlocked(_ channels: [Channel]) -> [Channel] {
        channels.filter { !organization.isHidden($0) && !parental.isLocked(.live, $0.groupName) }
    }

    private func channelRow(title: String, channels: [Channel], reorder: @escaping (String, String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.arjo(.headline)).padding(.horizontal, 48)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Layout.gridGap) {
                    ForEach(channels) { channel in
                        ChannelTile(channel: channel, nowNext: model.epg.nowNext(for: channel), onDropChannel: { reorder($0, channel.id) }) {
                            model.play(channel, in: channels)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 16)
            }
        }
        .task(id: channels) { await model.epg.loadNowNext(for: channels) }
    }
}

private struct GroupRow: View {
    private struct LoadKey: Hashable {
        let group: ChannelGroup
        let epgRevision: Int
        let isLocked: Bool
        let organizationRevision: Int
    }

    let group: ChannelGroup
    let model: LiveTVViewModel
    @Environment(ParentalControl.self) private var parental
    @Environment(OrganizationModel.self) private var organization
    @State private var channels: [Channel] = []
    /// Alle Sender der Gruppe, auch ausgeblendete: die eigene Reihenfolge bezieht sich auf sie.
    @State private var all: [Channel] = []
    @State private var loadFailed = false

    var body: some View {
        Group {
            if parental.isLocked(.live, group.name) {
                LockedGroupRow(name: group.name) { parental.requestUnlock() }
            } else {
                row
            }
        }
        .task(id: LoadKey(group: group, epgRevision: model.epg.revision, isLocked: parental.isLocked(.live, group.name), organizationRevision: organization.revision)) {
            guard !parental.isLocked(.live, group.name) else {
                channels = []
                return
            }
            do {
                all = try await model.channels(in: group)
                channels = organization.visible(organization.ordered(all))
                loadFailed = false
            } catch {
                loadFailed = true
                return
            }
            await model.epg.loadNowNext(for: channels)
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(organization.name(forGroup: group.name, in: .live)).font(.arjo(.headline))
                Text("\(group.channelCount)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 48)
            .groupMenu(group.name, area: .live, groups: model.groups, organization: organization)

            if loadFailed {
                Text("Die Sender dieser Gruppe konnten nicht geladen werden.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 48)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Layout.gridGap) {
                        ForEach(channels) { channel in
                            ChannelTile(channel: channel, nowNext: model.epg.nowNext(for: channel), onDropChannel: { dragged in
                                Task { await organization.moveChannel(dragged, to: channel.id, among: all) }
                            }) {
                                model.play(channel, in: channels)
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}


/// Grüner Punkt: Playlist aktiv. Roter Punkt: Problem. Grauer Punkt: noch nicht geprüft.
struct PlaylistStatusDot: View {
    let health: LiveTVViewModel.Health

    private var color: Color {
        switch health {
        case .unknown: .gray
        case .ok: .green
        case .problem: .red
        }
    }

    private var label: String {
        switch health {
        case .unknown: String(localized: "Playlist wird geprüft")
        case .ok: String(localized: "Playlist aktiv")
        case .problem(let reason): String(localized: "Playlist-Problem: \(reason)")
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .padding(.horizontal, 6)
            .help(label)
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}
