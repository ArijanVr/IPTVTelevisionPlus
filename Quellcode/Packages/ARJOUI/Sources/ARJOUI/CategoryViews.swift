import ARJOCore
import SwiftUI

/// Kachel einer Live-Kategorie: Farbverlauf aus dem Namen, Symbol, Titel und Anzahl.
struct CategoryTile: View {
    let group: ChannelGroup
    let isLocked: Bool
    @Environment(OrganizationModel.self) private var organization

    #if os(tvOS)
    static let size = CGSize(width: 320, height: 180)
    #else
    static let size = CGSize(width: 170, height: 100)
    #endif

    private var symbol: String { Self.symbol(for: group.name) }

    /// SF Symbol passend zum Namen der Kategorie (Sport, News, Kinder …), sonst ein Fernseher.
    static func symbol(for groupName: String) -> String {
        let name = groupName.lowercased()
        let table: [(keywords: [String], symbol: String)] = [
            (["sport", "dazn", "liga", "premier"], "sportscourt"),
            (["news", "nachricht", "info"], "newspaper"),
            (["kind", "kids", "junior", "cartoon"], "figure.and.child.holdinghands"),
            (["film", "movie", "kino", "cinema"], "film"),
            (["music", "musik", "radio"], "music.note"),
            (["doku", "doc", "natur", "history"], "globe.europe.africa"),
            (["adult", "xxx", "18"], "lock"),
        ]
        return table.first { entry in entry.keywords.contains { name.contains($0) } }?.symbol ?? "tv"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: 0x2A2C2C), Color(hex: 0x1A1B1D)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: isLocked ? "lock.fill" : symbol)
                .font(.system(size: Self.size.height * 0.45, weight: .bold))
                .foregroundStyle(Color(hex: 0xFDFDFC).opacity(0.14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(organization.name(forGroup: group.name, in: .live)).font(.arjo(.headline)).lineLimit(2)
                (Text(verbatim: "\(group.channelCount) ") + Text("Sender")).font(.arjo(.small)).opacity(0.85)
            }
            .foregroundStyle(Color(hex: 0xFDFDFC))
            .padding(12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
        .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Eine Kategorie-Kachel als Schaltfläche: öffnet die Kategorie, bei Sperre fragt sie nach der PIN.
struct CategoryLink: View {
    let group: ChannelGroup
    let allGroups: [ChannelGroup]
    @Environment(ParentalControl.self) private var parental
    @Environment(OrganizationModel.self) private var organization

    var body: some View {
        let locked = parental.isLocked(.live, group.name)
        Group {
            if locked {
                Button { parental.requestUnlock() } label: { CategoryTile(group: group, isLocked: true) }
            } else {
                NavigationLink(value: group) { CategoryTile(group: group, isLocked: false) }
            }
        }
        .wideCardButtonStyle()
        .groupMenu(group.name, area: .live, groups: allGroups, organization: organization)
    }
}

/// Alle Kategorien als Kachelraster.
struct CategoryGrid: View {
    let groups: [ChannelGroup]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: CategoryTile.size.width), spacing: Theme.Layout.gridGap)], alignment: .leading, spacing: Theme.Layout.gridGap) {
                ForEach(groups) { CategoryLink(group: $0, allGroups: groups) }
            }
            .padding(48)
        }
        .focusBackdrop()
    }
}

/// Eine einzelne Kategorie mit allen Sendern als Raster.
struct CategoryDetailView: View {
    let group: ChannelGroup
    let model: LiveTVViewModel
    @Environment(OrganizationModel.self) private var organization
    @Environment(ParentalControl.self) private var parental
    @State private var channels: [Channel] = []
    @State private var all: [Channel] = []
    @State private var loadFailed = false

    private struct LoadKey: Hashable {
        let group: ChannelGroup
        let organizationRevision: Int
    }

    @Environment(\.channelTileStyle) private var tileStyle

    var body: some View {
        ScrollView {
            if loadFailed {
                Text("Die Sender dieser Gruppe konnten nicht geladen werden.").foregroundStyle(.secondary).padding(48)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileStyle.artworkSize.width), spacing: Theme.Layout.gridGap)], alignment: .leading, spacing: Theme.Layout.gridGap) {
                    ForEach(channels) { channel in
                        ChannelTile(channel: channel, nowNext: model.epg.nowNext(for: channel), onDropChannel: { dragged in
                            Task { await organization.moveChannel(dragged, to: channel.id, among: all) }
                        }) {
                            model.play(channel, in: channels)
                        }
                    }
                }
                .padding(48)
            }
        }
        .focusBackdrop()
        .navigationTitle(organization.name(forGroup: group.name, in: .live))
        .task(id: LoadKey(group: group, organizationRevision: organization.revision)) {
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
}
