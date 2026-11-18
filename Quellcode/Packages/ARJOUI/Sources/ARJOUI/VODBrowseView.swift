import ARJOCore
import SwiftUI

public struct VODBrowseView: View {
    @Bindable private var catalog: VODCatalogModel
    private let player: VODPlayerModel
    @Environment(OrganizationModel.self) private var organization

    public init(catalog: VODCatalogModel, player: VODPlayerModel) {
        self.catalog = catalog
        self.player = player
    }

    private var title: LocalizedStringKey { catalog.kind == .movie ? "Filme" : "Serien" }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone (kompakt) behält die Reihen, alle breiten Layouts zeigen Kategorien links und Poster rechts.
    private var usesSplit: Bool { sizeClass != .compact }
    #else
    private var usesSplit: Bool { true }
    #endif

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem {
                        Menu {
                            Button("Liste aktualisieren") { Task { await catalog.refresh() } }
                                .disabled(catalog.isRefreshing)
                        } label: {
                            if catalog.isRefreshing { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                        }
                    }
                }
                .navigationDestination(for: VODItem.self) { item in
                    switch item.kind {
                    case .movie: MovieDetailView(item: item, catalog: catalog, player: player)
                    case .series: SeriesDetailView(item: item, catalog: catalog, player: player)
                    }
                }
        }
        .task { await catalog.load() }
        .alert(
            "Aktualisieren fehlgeschlagen",
            isPresented: Binding(get: { catalog.refreshError != nil }, set: { if !$0 { catalog.refreshError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(catalog.refreshError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch catalog.phase {
        case .loading:
            VStack(spacing: 20) {
                ProgressView()
                Text(LocalizedStringKey(catalog.kind == .movie ? "Filme werden geladen …" : "Serien werden geladen …")).foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(spacing: 24) {
                Text(message).multilineTextAlignment(.center)
                Button("Erneut versuchen") { Task { await catalog.load() } }
            }
            .padding(40)
        case .ready where catalog.groups.isEmpty:
            Text("Dein Anbieter liefert hier keine Inhalte.").foregroundStyle(.secondary)
        case .ready where usesSplit:
            CategorySplitView(catalog: catalog)
        case .ready:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(organization.visible(catalog.groups, in: catalog.kind == .movie ? .movie : .series)) { group in
                        GroupRow(group: group, catalog: catalog)
                    }
                }
                .padding(.vertical, 24)
            }
            .focusBackdrop()
        }
    }
}

private struct GroupRow: View {
    private struct LoadKey: Hashable {
        let group: ChannelGroup
        let isLocked: Bool
    }

    let group: ChannelGroup
    let catalog: VODCatalogModel
    @Environment(ParentalControl.self) private var parental
    @Environment(OrganizationModel.self) private var organization
    @State private var items: [VODItem] = []
    @State private var loadFailed = false

    private var area: GroupArea { catalog.kind == .movie ? .movie : .series }

    var body: some View {
        Group {
            if parental.isLocked(area, group.name) {
                LockedGroupRow(name: group.name) { parental.requestUnlock() }
            } else {
                row
            }
        }
        .task(id: LoadKey(group: group, isLocked: parental.isLocked(area, group.name))) {
            guard !parental.isLocked(area, group.name) else {
                items = []
                return
            }
            do {
                items = try await catalog.items(in: group)
                loadFailed = false
            } catch {
                loadFailed = true
            }
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(organization.name(forGroup: group.name, in: area)).font(.arjo(.headline))
                Text("\(group.channelCount)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 48)
            .groupMenu(group.name, area: area, groups: catalog.groups, organization: organization)

            if loadFailed {
                Text("Die Inhalte dieser Gruppe konnten nicht geladen werden.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 48)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Layout.gridGap) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                PosterCard(
                                    title: item.name,
                                    subtitle: [item.year, item.rating.map(Formatting.rating)].compactMap { $0 }.joined(separator: " · "),
                                    posterURL: item.posterURL
                                )
                            }
                            .posterButtonStyle()
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}
