import ARJOCore
import SwiftUI

struct SearchView: View {
    @Bindable var model: SearchModel
    let session: ProfileSession
    @Environment(OrganizationModel.self) private var organization

    private struct SearchKey: Hashable {
        let query: String
        let isUnlocked: Bool
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Suche")
                .searchable(text: $model.query, prompt: "Sender, Filme, Serien, Sendungen")
                .searchScopes($model.scope) {
                    ForEach(SearchModel.Scope.allCases) { Text($0.title).tag($0) }
                }
                .onSubmit(of: .search) { model.rememberQuery() }
                .navigationDestination(for: ChannelGroup.self) { CategoryDetailView(group: $0, model: session.live) }
                .navigationDestination(for: VODItem.self) { item in
                    switch item.kind {
                    case .movie: MovieDetailView(item: item, catalog: session.movies, player: session.vodPlayer)
                    case .series: SeriesDetailView(item: item, catalog: session.series, player: session.vodPlayer)
                    }
                }
        }
        .simultaneousGesture(TapGesture().onEnded { model.rememberQuery() })
        .task(id: SearchKey(query: model.query, isUnlocked: session.parental.isUnlocked)) {
            // Kurz warten, damit nicht bei jedem Buchstaben (oder Diktat-Zwischenstand) gesucht wird.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await model.search()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isQueryTooShort {
            idle
        } else if model.state == .searching, model.results.isEmpty, matchingGroups.isEmpty {
            ProgressView()
        } else if model.state == .done, model.results.isEmpty, matchingGroups.isEmpty {
            Text("Nichts gefunden. Versuch ein anderes Wort.").font(.arjo(.body)).foregroundStyle(Theme.textSecondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    if let warning = model.warning {
                        Text(warning).foregroundStyle(.secondary).padding(.horizontal, 48)
                    }
                    if model.scope == .all || model.scope == .live {
                        categorySection
                        channelSection
                    }
                    if model.scope == .all || model.scope == .movies {
                        vodSection(title: "Filme", items: model.results.movies.filter { !organization.isHidden(group: $0.groupName, in: .movie) })
                    }
                    if model.scope == .all || model.scope == .series {
                        vodSection(title: "Serien", items: model.results.series.filter { !organization.isHidden(group: $0.groupName, in: .series) })
                    }
                    if model.scope == .all || model.scope == .programmes {
                        programmeSection
                    }
                }
                .padding(.vertical, 24)
            }
            .focusBackdrop()
        }
    }

    /// Kategorien, deren Name zum Suchbegriff passt (ohne gesperrte oder ausgeblendete).
    private var matchingGroups: [ChannelGroup] {
        guard model.scope == .all || model.scope == .live, !model.isQueryTooShort else { return [] }
        return organization.visible(session.live.groups, in: .live).filter {
            organization.name(forGroup: $0.name, in: .live).localizedStandardContains(model.trimmedQuery)
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        let groups = matchingGroups
        if !groups.isEmpty {
            section("Kategorien") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Layout.gridGap) {
                        ForEach(groups) { CategoryLink(group: $0, allGroups: groups) }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    /// Ohne Suchbegriff: die zuletzt gesuchten Begriffe zum schnellen Wiederfinden.
    @ViewBuilder
    private var idle: some View {
        if model.recentQueries.isEmpty {
            Text("Suche nach Sendern, Filmen, Serien und Sendungen. Tippe oder diktiere über die Mikrofon-Taste der Tastatur bzw. der Siri Remote.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(48)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Zuletzt gesucht").font(.arjo(.headline))
                        Spacer()
                        Button("Löschen") { model.clearRecentQueries() }
                    }
                    ForEach(model.recentQueries, id: \.self) { term in
                        Button { model.query = term } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .buttonStyle(.plain)
                        .contentSurface(cornerRadius: Theme.fieldRadius)
                    }
                }
                .padding(48)
            }
        }
    }

    @ViewBuilder
    private var channelSection: some View {
        let channels = model.results.channels.filter { !organization.isHidden($0) }
        if !channels.isEmpty {
            section("Live TV") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Layout.gridGap) {
                        ForEach(channels) { channel in
                            ChannelTile(channel: channel, nowNext: session.live.epg.nowNext(for: channel)) {
                                model.rememberQuery()
                                session.live.play(channel, in: channels)
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                }
            }
            .task(id: channels) { await session.live.epg.loadNowNext(for: channels) }
        }
    }

    @ViewBuilder
    private func vodSection(title: String, items: [VODItem]) -> some View {
        if !items.isEmpty {
            section(title) {
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

    @ViewBuilder
    private var programmeSection: some View {
        let programmes = model.results.programmes.filter { !organization.isHidden($0.channel) }
        if !programmes.isEmpty {
            section("Sendungen") {
                LazyVStack(spacing: 10) {
                    ForEach(programmes) { result in
                        ProgrammeRow(result: result) {
                            session.live.play(result.channel, in: [result.channel])
                        }
                    }
                }
                .padding(.horizontal, 48)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.arjo(.headline)).padding(.horizontal, 48)
            content()
        }
    }
}

private struct ProgrammeRow: View {
    let result: SearchModel.ProgrammeResult
    let play: () -> Void
    @Environment(\.displayTimeZone) private var zone

    var body: some View {
        let programme = result.programme
        let airing = programme.isAiring(at: Date())
        Button(action: play) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(programme.title).font(.arjo(.headline)).lineLimit(1)
                    Text("\(result.channel.name) · \(Formatting.weekdayAndTime(programme.start, in: zone)) – \(Formatting.time(programme.stop, in: zone))")
                        .font(.arjo(.small))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if airing {
                    Text("Läuft jetzt").font(.arjo(.smallMedium)).foregroundStyle(.tint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.fieldRadius))
        .accessibilityHint(airing ? Text("Sender öffnen") : Text("Sender öffnen, die Sendung läuft später"))
    }
}
