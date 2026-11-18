import ARJOCore
import SwiftUI

/// Kategorien als zweispaltige Ansicht (Brandguide S. 10, Referenz «Movies · Categories»):
/// links die Kategorien mit Anzahl, rechts das Posterraster der gewählten Kategorie.
/// Pfeiltasten und Fernbedienung wie bisher: Fokus auf einer Kategorie zeigt rechts ihre Titel, Rechts springt ins Raster.
struct CategorySplitView: View {
    let catalog: VODCatalogModel
    @Environment(OrganizationModel.self) private var organization
    @Environment(ParentalControl.self) private var parental
    @State private var selectedID: String?
    @State private var items: [VODItem] = []
    @State private var loadFailed = false
    @FocusState private var focusedID: String?

    private var area: GroupArea { catalog.kind == .movie ? .movie : .series }
    private var groups: [ChannelGroup] { organization.visible(catalog.groups, in: area) }
    private var selected: ChannelGroup? { groups.first { $0.id == selectedID } ?? groups.first }

    #if os(tvOS)
    private let listWidth: CGFloat = 520
    #else
    private let listWidth: CGFloat = 280
    #endif

    private struct LoadKey: Hashable {
        let group: ChannelGroup?
        let isLocked: Bool
        let revision: Int
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Layout.gridGap) {
            list
                .frame(width: listWidth)
            grid
        }
        .padding(.horizontal, Theme.Layout.safeX)
        .padding(.top, 8)
        .splitFocusSection()
        .focusBackdrop()
        .task(id: LoadKey(group: selected, isLocked: selected.map { parental.isLocked(area, $0.name) } ?? false, revision: organization.revision)) {
            await loadItems()
        }
        .onChange(of: focusedID) { _, new in
            if let new { selectedID = new }
        }
    }

    // MARK: Liste

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(groups) { group in
                    Button {
                        selectedID = group.id
                    } label: {
                        CategoryRow(
                            title: organization.name(forGroup: group.name, in: area),
                            count: group.channelCount,
                            isLocked: parental.isLocked(area, group.name),
                            isSelected: group.id == selected?.id
                        )
                    }
                    .buttonStyle(CategoryRowButtonStyle(isSelected: group.id == selected?.id))
                    .focused($focusedID, equals: group.id)
                    .groupMenu(group.name, area: area, groups: catalog.groups, organization: organization)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
        }
        .splitFocusSection()
    }

    // MARK: Raster

    @ViewBuilder
    private var grid: some View {
        if let group = selected, parental.isLocked(area, group.name) {
            VStack(spacing: 16) {
                Image(systemName: "lock").font(.arjo(.display)).foregroundStyle(Theme.textSecondary)
                Text("Gesperrt").font(.arjo(.headline))
                Button("Entsperren") { parental.requestUnlock() }.buttonStyle(PillButtonStyle(isProminent: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            Text("Die Inhalte dieser Gruppe konnten nicht geladen werden.")
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: PosterCard.size.width), spacing: Theme.Layout.gridGap, alignment: .top)], alignment: .leading, spacing: Theme.Layout.gridGap) {
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
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            }
        }
    }

    private func loadItems() async {
        guard let group = selected, !parental.isLocked(area, group.name) else {
            items = []
            return
        }
        // Beim schnellen Durchschalten nicht jede Zwischenstation laden.
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        do {
            let loaded = try await catalog.items(in: group)
            if Task.isCancelled { return }
            items = loaded
            loadFailed = false
        } catch {
            if Task.isCancelled { return }
            loadFailed = true
        }
    }
}

private struct CategoryRow: View {
    let title: String
    let count: Int
    let isLocked: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isLocked { Image(systemName: "lock").font(.arjo(.small)) }
            Text(verbatim: title).font(.arjo(isSelected ? .bodyMedium : .body)).lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: "\(count)").font(.arjo(.small)).foregroundStyle(Theme.textSecondary).monospacedDigit()
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.minHit, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CategoryRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, isSelected: isSelected)
    }

    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
            configuration.label
                .background {
                    shape.fill(isSelected || isFocused ? Theme.surface : Theme.text.opacity(isHovered ? 0.06 : 0))
                }
                .modifier(FocusLift(shape: shape, isActive: isFocused))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                #if !os(tvOS)
                .onHover { isHovered = $0 }
                #endif
                .contentShape(shape)
        }
    }
}

private extension View {
    /// Fokusbereich für Pfeiltasten (tvOS, macOS); unter iOS nicht verfügbar.
    @ViewBuilder
    func splitFocusSection() -> some View {
        #if os(iOS)
        self
        #else
        focusSection()
        #endif
    }
}
