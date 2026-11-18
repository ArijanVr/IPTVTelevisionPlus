import ARJOCore
import SwiftUI

/// Tab «Jetzt» im Apple-TV-Stil: Titelbild-Karussell, Weiterschauen, «Jetzt im TV» und Reihen, mit Liquid Glass.
/// Mit `isLibrary` derselbe Aufbau als Tab «Mediathek» (Brandguide S. 9): Weiterschauen, Zuletzt gesehen,
/// Favoriten und eigene Ordner, ohne Titelbild.
struct HomeView: View {
    let session: ProfileSession
    var isLibrary = false
    @Environment(ParentalControl.self) private var parental
    @Environment(MultiviewModel.self) private var multiview: MultiviewModel?
    @Environment(\.displayTimeZone) private var zone
    @Environment(SettingsModel.self) private var settings: SettingsModel?
    @Environment(\.openListEditor) private var openListEditor
    @State private var featuredIndex = 0

    private var home: HomeModel { session.home }
    private var live: LiveTVViewModel { session.live }
    private var organization: OrganizationModel { session.organization }

    private let margin = Theme.Layout.safeX

    private func isShown(_ channel: Channel) -> Bool {
        !organization.isHidden(channel) && !parental.isLocked(.live, channel.groupName)
    }

    private func isShown(_ progress: WatchProgress) -> Bool {
        !parental.isLocked(progress.target.kind == .movie ? .movie : .series, progress.target.groupName)
    }

    private func isShown(_ item: VODItem) -> Bool {
        !parental.isLocked(item.kind == .movie ? .movie : .series, item.groupName)
    }

    /// Inhalte der Startseite, schon gefiltert (ausgeblendet, gesperrt).
    private struct Content {
        var resumable: [WatchProgress]
        var lastChannel: Channel?
        var favorites: [Channel]
        var folders: [(ChannelFolder, [Channel])]
        var movies: [VODItem]
        var series: [VODItem]
        var featured: [HomeModel.Featured]
        var onAir: [Channel]
        var categories: [ChannelGroup]
    }

    private func showsHero(_ content: Content) -> Bool {
        sections.contains(.hero) && !content.featured.isEmpty
    }

    private var sections: [HomeSection] {
        if isLibrary { return [.continueWatching, .lastChannel, .favorites, .folders] }
        return settings?.settings.visibleHomeSections ?? HomeSection.allCases
    }

    private var title: LocalizedStringKey { isLibrary ? "Mediathek" : "Jetzt" }

    var body: some View {
        let resumable = home.continueWatching.filter(isShown)
        let lastChannel = live.lastChannel.flatMap { isShown($0) ? $0 : nil }
        let favorites = organization.favorites.filter(isShown)
        let folders = organization.folders.compactMap { folder -> (ChannelFolder, [Channel])? in
            let channels = (organization.folderChannels[folder.id] ?? []).filter(isShown)
            return channels.isEmpty ? nil : (folder, channels)
        }
        let content = Content(
            resumable: resumable,
            lastChannel: lastChannel,
            favorites: favorites,
            folders: folders,
            movies: home.recentMovies.filter(isShown),
            series: home.recentSeries.filter(isShown),
            featured: home.featuredItems(resumable: resumable, lastChannel: lastChannel, favorites: favorites),
            onAir: Array(([lastChannel].compactMap { $0 } + favorites).uniqued().prefix(5)),
            categories: organization.visible(live.groups, in: .live)
        )
        let liveChannels = (content.onAir + favorites + folders.flatMap(\.1)).uniqued()
        let isEmpty = isLibrary
            ? content.resumable.isEmpty && content.lastChannel == nil && content.favorites.isEmpty && content.folders.isEmpty
            : content.featured.isEmpty && content.movies.isEmpty && content.series.isEmpty

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Layout.sectionGap) {
                    if !showsHero(content) {
                        header
                    }
                    if isEmpty {
                        // Leer-Zustand nach Brandguide S. 12: ein Satz, eine Aktion; der Tab bleibt sichtbar.
                        VStack(alignment: .leading, spacing: 8) {
                            if isLibrary {
                                Text("Noch nichts gemerkt.").font(.arjo(.title2))
                            }
                            Text(home.loadFailed && !isLibrary
                                 ? "Diese Seite konnte nicht geladen werden."
                                 : isLibrary
                                 ? "Markiere einen Sender als Favorit oder starte einen Film. Er erscheint dann hier."
                                 : "Hier erscheinen zuletzt gesehene Sender, Favoriten und angefangene Filme.")
                                .font(.arjo(.body))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, margin)
                    }
                    ForEach(sections) { section in
                        self.section(section, content)
                    }
                    Button { openListEditor(isLibrary ? .channels : .home) } label: {
                        Label(isLibrary ? "Listen bearbeiten" : "«Jetzt» anpassen", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(PillButtonStyle())
                    .padding(.horizontal, margin)
                }
                .padding(.bottom, 48)
            }
            #if !os(tvOS)
            // Titelbild läuft in ARJO Black aus: dieselbe Farbe dahinter, sonst entsteht eine Kante.
            .background { ThemeBackground() }
            #endif
            .focusBackdrop()
            #if os(iOS)
            // Nur das Titelbild läuft bis unter die Statusleiste; ohne Titelbild bleibt der Kopf im sicheren Bereich.
            .ignoresSafeArea(edges: showsHero(content) ? .top : [])
            .toolbarVisibility(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                ProfileButton(profile: session.profile)
                    .padding(.trailing, margin)
                    .padding(.top, 4)
            }
            #elseif os(macOS)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            #else
            .navigationTitle(title)
            #endif
            .navigationDestination(for: ChannelGroup.self) { CategoryDetailView(group: $0, model: live) }
            .navigationDestination(for: VODItem.self) { item in
                switch item.kind {
                case .movie: MovieDetailView(item: item, catalog: session.movies, player: session.vodPlayer)
                case .series: SeriesDetailView(item: item, catalog: session.series, player: session.vodPlayer)
                }
            }
            .task(id: liveChannels.map(\.id)) { await live.epg.loadNowNext(for: liveChannels) }
        }
        .task(id: session.vodPlayer.progressRevision) { await home.load() }
    }

    /// Kopf ohne Titelbild: Marke und Begrüssung im Stil des Guides.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "IP Television+")
            BrandTitle(text: isLibrary ? String(localized: "Mediathek") : String(localized: "Alles an einem Ort"), style: .display)
        }
        .padding(.horizontal, margin)
        #if os(iOS)
        .padding(.trailing, 52) // Platz für das Profil-Symbol oben rechts
        #endif
        .padding(.top, 24)
    }

    @ViewBuilder
    private func section(_ section: HomeSection, _ content: Content) -> some View {
        switch section {
        case .hero:
            if !content.featured.isEmpty {
                HeroCarousel(items: content.featured, index: $featuredIndex, margin: margin) { hero($0) }
            }
        case .continueWatching:
            if !content.resumable.isEmpty {
                row("Weiterschauen") {
                    ForEach(content.resumable) { progress in
                        Button { Task { await session.vodPlayer.play(progress.target) } } label: {
                            WideCard(
                                imageURL: progress.target.posterURL, title: progress.target.title,
                                subtitle: progress.target.subtitle, fraction: progress.fraction, placeholder: "film"
                            )
                        }
                        .buttonStyle(ArtworkButtonStyle())
                        .contextMenu {
                            Button("Als gesehen markieren") {
                                Task { await session.vodPlayer.setWatched(true, target: progress.target) }
                            }
                        }
                    }
                }
            }
        case .onAir:
            if !content.onAir.isEmpty { nowOnTV(content.onAir) }
        case .lastChannel:
            if let lastChannel = content.lastChannel {
                row("Zuletzt gesehen") {
                    // Setzt auch eine Timeshift-Stelle fort, die auf einem anderen Gerät gespeichert wurde.
                    ChannelTile(channel: lastChannel, nowNext: live.epg.nowNext(for: lastChannel), onDropChannel: nil) {
                        Task { await live.resumeLastChannel() }
                    }
                }
            }
        case .favorites:
            if !content.favorites.isEmpty {
                row("Favoriten") {
                    ForEach(content.favorites) { channel in
                        liveCard(channel, queue: content.favorites) { dragged in
                            Task { await organization.moveFavorite(dragged, to: channel.id) }
                        }
                    }
                }
            }
        case .folders:
            ForEach(content.folders, id: \.0.id) { folder, channels in
                row(Text(verbatim: folder.name)) {
                    ForEach(channels) { channel in
                        liveCard(channel, queue: channels) { dragged in
                            Task { await organization.move(dragged, to: channel.id, in: folder) }
                        }
                    }
                }
            }
        case .categories:
            if !content.categories.isEmpty {
                row("Kategorien") {
                    ForEach(content.categories) { CategoryLink(group: $0, allGroups: content.categories) }
                }
            }
        case .movies:
            if !content.movies.isEmpty {
                row("Neue Filme") { ForEach(content.movies) { poster($0) } }
            }
        case .series:
            if !content.series.isEmpty {
                row("Neue Serien") { ForEach(content.series) { poster($0) } }
            }
        }
    }

    // MARK: Bausteine

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        row(Text(title), content: content)
    }

    private func row<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowTitleGap) {
            title.font(.arjo(.headline)).padding(.horizontal, margin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Layout.gridGap) { content() }
                    .padding(.horizontal, margin)
                    .padding(.vertical, 16)
            }
            .scrollClipDisabled()
        }
    }

    private func poster(_ item: VODItem) -> some View {
        NavigationLink(value: item) {
            PosterCard(title: item.name, subtitle: nil, posterURL: item.posterURL)
        }
        .posterButtonStyle()
    }

    private func liveCard(_ channel: Channel, queue: [Channel], onDrop: ((String) -> Void)? = nil) -> some View {
        ChannelTile(channel: channel, nowNext: live.epg.nowNext(for: channel), onDropChannel: onDrop) {
            live.play(channel, in: queue)
        }
    }

    /// Programmführer in Kurzform: pro Sender die laufende und die nächste Sendung.
    private func nowOnTV(_ channels: [Channel]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jetzt im TV").font(.arjo(.headline))
            VStack(spacing: 10) {
                ForEach(channels) { channel in
                    NowRow(channel: channel, nowNext: live.epg.nowNext(for: channel), zone: zone) {
                        live.play(channel, in: channels)
                    }
                    .channelMenu(channel, organization: organization, multiview: multiview)
                }
            }
        }
        .padding(.horizontal, margin)
    }

    @ViewBuilder
    private func hero(_ featured: HomeModel.Featured) -> some View {
        switch featured {
        case .resume(let progress):
            HeroSlide(
                imageURL: progress.target.posterURL, isLogo: false,
                eyebrow: "Weiterschauen", title: progress.target.title,
                subtitle: progress.target.subtitle, detail: nil,
                fraction: progress.fraction, actionTitle: "Fortsetzen", margin: margin,
                action: { Task { await session.vodPlayer.play(progress.target) } },
                secondaryIcon: "checkmark",
                secondaryLabel: "Als gesehen markieren",
                secondary: { Task { await session.vodPlayer.setWatched(true, target: progress.target) } }
            )
        case .channel(let channel):
            let now = live.epg.nowNext(for: channel)?.now
            HeroSlide(
                imageURL: channel.logoURL, isLogo: true,
                eyebrow: channel == live.lastChannel ? "Zuletzt gesehen" : "Favorit",
                title: organization.name(for: channel),
                subtitle: now.map { "\($0.title) · \(Formatting.time($0.start, in: zone)) – \(Formatting.time($0.stop, in: zone))" },
                detail: now?.description,
                fraction: now?.progress(at: Date()) ?? 0, actionTitle: "Live ansehen", margin: margin,
                action: { live.play(channel, in: [channel]) },
                secondaryIcon: organization.isFavorite(channel) ? "star.fill" : "star",
                secondaryLabel: organization.isFavorite(channel) ? "Aus Favoriten entfernen" : "Zu Favoriten",
                secondary: { Task { await organization.toggleFavorite(channel) } }
            )
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension View {
    /// Breite Karte: auf Apple TV hebt sie sich beim Fokus an, auf iPad und Mac reagiert sie auf den Zeiger.
    @ViewBuilder
    func wideCardButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(TileButtonStyle())
        #else
        buttonStyle(.plain).pointerEffect()
        #endif
    }
}

// MARK: - Titelbild

/// Karussell der Titelbilder mit Seitenpunkten und Weiter-Taste (auf iOS auch per Wischen).
private struct HeroCarousel<Slide: View>: View {
    let items: [HomeModel.Featured]
    @Binding var index: Int
    let margin: CGFloat
    @ViewBuilder let slide: (HomeModel.Featured) -> Slide

    #if os(tvOS)
    private let height: CGFloat = 640
    #else
    private let height: CGFloat = 420
    #endif

    private var current: Int { min(index, items.count - 1) }

    var body: some View {
        ZStack(alignment: .bottom) {
            slide(items[current])
                .frame(height: height)
                .id(items[current])
                .transition(.opacity)
            if items.count > 1 {
                HStack(spacing: 8) {
                    ForEach(items.indices, id: \.self) { position in
                        Capsule()
                            .fill(position == current ? Color.primary : Color.primary.opacity(0.3))
                            .frame(width: position == current ? 22 : 8, height: 8)
                    }
                }
                .padding(10)
                .glass(cornerRadius: Theme.tileRadius)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            }
        }
        .frame(height: height)
        .overlay(alignment: .trailing) {
            if items.count > 1 {
                Button { advance(by: 1) } label: { Image(systemName: "chevron.right") }
                    .glassButtonStyle()
                    .padding(.trailing, margin)
                    .accessibilityLabel("Nächstes Titelbild")
            }
        }
        #if os(iOS)
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            advance(by: value.translation.width < 0 ? 1 : -1)
        })
        #endif
        .animation(.smooth, value: current)
    }

    private func advance(by offset: Int) {
        index = (current + offset + items.count) % items.count
    }
}

extension HomeModel.Featured: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .resume(let progress): hasher.combine(progress.id)
        case .channel(let channel): hasher.combine(channel.id)
        }
    }
}

/// Eine Seite des Karussells: unscharfer Vollbild-Hintergrund, Titel, Beschreibung und Glas-Tasten.
private struct HeroSlide: View {
    let imageURL: URL?
    let isLogo: Bool
    let eyebrow: LocalizedStringKey
    let title: String
    let subtitle: String?
    let detail: String?
    let fraction: Double
    let actionTitle: LocalizedStringKey
    let margin: CGFloat
    let action: () -> Void
    let secondaryIcon: String
    let secondaryLabel: LocalizedStringKey
    let secondary: () -> Void
    @Environment(\.colorScheme) private var scheme

    /// Farbe, in die das Bild ausläuft: folgt dem hellen oder dunklen Erscheinungsbild.
    private var base: Color { Theme.background(scheme) }

    var body: some View {
        // Der Text bestimmt die Grösse; Bild und Verläufe liegen dahinter und können das Layout nicht aufblähen.
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            // Nur das Bild läuft gespiegelt und verwischt unter die Seitenleiste, nicht Text und Tasten.
            .background { backdrop.extendsBeneathSidebar() }
    }

    private var backdrop: some View {
        ZStack {
            if isLogo {
                // Winziges Bild, hochgezogen: weicher Farbhintergrund ohne Weichzeichner.
                CachedImage(url: imageURL, contentMode: .fill, maxPixel: 48, interpolation: .high) { Color.primary.opacity(0.06) }
                    .opacity(0.6)
                CachedImage(url: imageURL, contentMode: .fit, maxPixel: 600) { Color.clear }
                    .frame(maxWidth: 360, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, margin + 40)
                    .padding(.top, 90)
            } else {
                CachedImage(url: imageURL, contentMode: .fill, maxPixel: 800) { Color.primary.opacity(0.06) }
            }
            LinearGradient(colors: [.clear, base], startPoint: UnitPoint(x: 0.5, y: 0.35), endPoint: .bottom)
            LinearGradient(colors: [base.opacity(0.9), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))
        }
        .reportsBackdrop(imageURL)
        .clipped()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: eyebrow)
            BrandTitle(text: title, style: .display)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let subtitle {
                Text(subtitle).font(.arjo(.headline)).foregroundStyle(.primary.opacity(0.85)).lineLimit(1)
            }
            if let detail, !detail.isEmpty {
                Text(detail).font(.arjo(.body)).foregroundStyle(.secondary).lineLimit(2)
            }
            if fraction > 0, fraction < 1 {
                ProgressView(value: fraction).frame(maxWidth: 320).tint(Theme.glut)
            }
            HStack(spacing: 14) {
                Button(action: action) {
                    Label(actionTitle, systemImage: "play.fill")
                }
                .buttonStyle(PillButtonStyle(isProminent: true))
                Button(action: secondary) {
                    Label(secondaryLabel, systemImage: secondaryIcon)
                }
                .buttonStyle(PillButtonStyle())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: 680, alignment: .leading)
        .padding(.horizontal, margin)
        .padding(.bottom, 64)
        .foregroundStyle(.primary)
    }
}

// MARK: - Karten und Zeilen

/// Breite 16:9-Karte: Bild mit Titel darin, feiner Glut-Fortschritt am unteren Rand, Untertitel darunter.
private struct WideCard: View {
    let imageURL: URL?
    let title: String
    let subtitle: String?
    var fraction: Double = 0
    let placeholder: String

    #if os(tvOS)
    private static let size = CGSize(width: 410, height: 231) // 4er-Raster 16:9
    #else
    private static let size = CGSize(width: 260, height: 146)
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CachedImage(url: imageURL, contentMode: .fill, maxPixel: 600) {
                ZStack {
                    Theme.raised
                    Image(systemName: placeholder).font(.arjo(.display)).foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipped()
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.arjo(.bodyMedium)).foregroundStyle(.white).lineLimit(1)
                    if fraction > 0, fraction < 1 {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.25))
                                Capsule().fill(Theme.glut).frame(width: proxy.size.width * fraction)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(14)
            }
            .reportsBackdrop(imageURL)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .modifier(ArtworkFocus())

            if let subtitle {
                Text(subtitle).font(.arjo(.small)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: Self.size.width, alignment: .leading)
    }
}

/// Zeile «Jetzt im TV»: Logo, laufende Sendung mit Fortschritt, danach die nächste.
private struct NowRow: View {
    let channel: Channel
    let nowNext: NowNext?
    let zone: TimeZone
    let action: () -> Void
    @Environment(OrganizationModel.self) private var organization

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                CachedImage(url: channel.logoURL, contentMode: .fit, maxPixel: 200) {
                    Image(systemName: "tv").foregroundStyle(.secondary)
                }
                .frame(width: 72, height: 48)
                .reportsBackdrop(channel.logoURL)

                VStack(alignment: .leading, spacing: 4) {
                    Text(organization.name(for: channel)).font(.arjo(.small)).foregroundStyle(.secondary).lineLimit(1)
                    if let now = nowNext?.now {
                        Text(now.title).font(.arjo(.bodyMedium)).lineLimit(1)
                        ProgressView(value: now.progress(at: Date())).tint(Theme.glut)
                    } else {
                        Text("Keine Sendungsdaten").font(.arjo(.body)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let next = nowNext?.next {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Formatting.time(next.start, in: zone)).font(.arjo(.small)).foregroundStyle(.secondary)
                        Text(next.title).font(.arjo(.body)).lineLimit(1)
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        #if os(tvOS)
        .buttonStyle(TileButtonStyle())
        #else
        .buttonStyle(.plain)
        .contentSurface(cornerRadius: Theme.tileRadius)
        .pointerEffect(highlight: true)
        #endif
        .accessibilityLabel(organization.name(for: channel))
    }
}
