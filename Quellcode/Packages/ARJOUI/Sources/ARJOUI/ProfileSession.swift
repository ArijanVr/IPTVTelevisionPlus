import ARJOCore
import SwiftUI
import ARJOPlayer

/// Alle Modelle eines angemeldeten Profils.
@MainActor
public final class ProfileSession {
    public let profile: Profile
    public let live: LiveTVViewModel
    public let movies: VODCatalogModel
    public let series: VODCatalogModel
    public let vodPlayer: VODPlayerModel
    public let home: HomeModel
    public let search: SearchModel
    public let parental: ParentalControl
    public let organization: OrganizationModel
    public let multiview: MultiviewModel
    /// Zustand des iCloud-Abgleichs (für alle Profile gleich).
    public let sync: any SyncMonitoring

    private let clearData: (UUID) async throws -> Void
    private var lastEPGOffset: TimeInterval?

    /// - Parameter clearData: Löscht Katalog, EPG und Film-/Serienlisten dieses Profils (nicht Zugangsdaten, Profil, Wiedergabestand).
    public init(
        profile: Profile,
        live: LiveTVViewModel,
        movies: VODCatalogModel,
        series: VODCatalogModel,
        vodPlayer: VODPlayerModel,
        home: HomeModel,
        search: SearchModel,
        parental: ParentalControl,
        organization: OrganizationModel,
        multiview: MultiviewModel,
        sync: (any SyncMonitoring)? = nil,
        clearData: @escaping (UUID) async throws -> Void
    ) {
        self.sync = sync ?? StaticSyncMonitor(status: .unavailable)
        self.clearData = clearData
        self.profile = profile
        self.live = live
        self.movies = movies
        self.series = series
        self.vodPlayer = vodPlayer
        self.home = home
        self.search = search
        self.parental = parental
        self.organization = organization
        self.multiview = multiview
        multiview.onWillPresent = { [live] in live.closePlayer() }
        // Beim Zappen und Starten zählen nur sichtbare, nicht gesperrte Gruppen.
        live.eligibleGroups = { [organization, parental] groups in
            organization.visible(groups, in: .live).filter { !parental.isLocked(.live, $0.name) }
        }
        vodPlayer.nextEpisodeProvider = { [series] in await series.nextEpisode(after: $0) }
    }

    /// Überträgt Einstellungen auf Player und Programmführer.
    public func apply(_ settings: AppSettings) {
        for engine in [live.engine, vodPlayer.engine] {
            engine.bufferDuration = settings.bufferSeconds
            engine.aspect = settings.aspect == .fill ? .fill : .fit
        }
        if let lastEPGOffset, lastEPGOffset != settings.epgOffset { live.epg.offsetChanged() }
        lastEPGOffset = settings.epgOffset
    }

    /// Spielt einen Eintrag aus «Weiterschauen» ab, den ein Link (Top Shelf) nennt.
    public func handle(_ url: URL) async {
        guard let id = DeepLink.playItemID(from: url) else { return }
        await home.load()
        guard let progress = home.continueWatching.first(where: { $0.id == id }) else { return }
        let target = progress.target
        guard !parental.isLocked(target.kind == .movie ? .movie : .series, target.groupName) else {
            parental.requestUnlock()
            return
        }
        await vodPlayer.play(target)
    }

    /// Löscht Wiedergabestand und zuletzt gesehenen Sender dieser Quelle (lokal und, mit Abgleich, auf allen Geräten).
    public func clearHistory() async {
        await vodPlayer.clearHistory()
        await live.clearHistory()
        await home.load()
    }

    /// Änderungen anderer Geräte (iCloud) oder Rückkehr in den Vordergrund: Nutzerdaten neu lesen.
    public func reloadUserData() async {
        await organization.load()
        await home.load()
        await live.refreshResumeState()
        vodPlayer.markProgressChanged()
    }

    /// App geht in den Hintergrund oder wird unterbrochen: offene Stände sofort speichern.
    public func persistPending() {
        vodPlayer.persistPending()
        live.persistPending()
    }

    public func start() async {
        #if os(iOS)
        CarPlayCoordinator.shared.attach(session: self)
        #endif
        await organization.load()
        await live.start()
    }

    /// Löscht die lokalen Listen und lädt sie neu.
    public func clearLocalData() async throws {
        try await clearData(profile.id)
        URLCache.shared.removeAllCachedResponses()
        await ImageLoader.shared.clear()
        await live.refreshCatalog()
        await movies.refresh()
        await series.refresh()
        await live.epg.refresh()
    }
}

/// Bereiche der App.
enum MainTab: Hashable {
    case home, live, movies, series, library, settings, search
}

struct MainTabView: View {
    @State private var backdrop = BackdropState()
    @State private var editorPage: ListEditorView.Page?
    @State private var selection: MainTab = .home
    #if !os(tvOS)
    @State private var showsSettings = false
    #endif
    #if !os(tvOS)
    @AppStorage("tv.sidebar.customization") private var customization = TabViewCustomization()
    #endif
    let session: ProfileSession
    let settings: SettingsModel
    let appModel: AppModel
    let backup: BackupService

    /// «Zurück zum Fernsehen»: setzt den zuletzt gesehenen Kanal fort (Filme und Serien beenden den Live-Stream).
    @ViewBuilder
    private var backToTV: some View {
        if session.live.lastChannel != nil, !session.live.isPlayerPresented {
            Button { Task { await session.live.resumeLastChannel() } } label: {
                Label("Zurück zum Fernsehen", systemImage: "tv.fill")
            }
            .buttonStyle(PillButtonStyle(isProminent: true))
            .padding(.trailing, Theme.Layout.safeX)
            #if os(iOS)
            .padding(.bottom, 80)
            #else
            .padding(.bottom, Theme.Layout.safeY)
            #endif
            .transition(.opacity)
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            // Tabs: Jetzt · Live · Filme · Serien · Mediathek, dazu Suche und Profil.
            Tab("Jetzt", systemImage: "house.fill", value: MainTab.home) {
                HomeView(session: session)
            }
            .customizationID("home")
            Tab("Live", systemImage: "dot.radiowaves.left.and.right", value: MainTab.live) {
                LiveTVView(model: session.live, parental: session.parental, organization: session.organization, onSignOut: { await appModel.signOut(session.profile) })
            }
            .customizationID("live")
            Tab("Filme", systemImage: "film.fill", value: MainTab.movies) {
                VODBrowseView(catalog: session.movies, player: session.vodPlayer)
            }
            .customizationID("movies")
            Tab("Serien", systemImage: "rectangle.stack.fill", value: MainTab.series) {
                VODBrowseView(catalog: session.series, player: session.vodPlayer)
            }
            .customizationID("series")
            Tab("Mediathek", systemImage: "books.vertical.fill", value: MainTab.library) {
                HomeView(session: session, isLibrary: true)
            }
            .customizationID("library")
            Tab(value: MainTab.search, role: .search) {
                SearchView(model: session.search, session: session)
            }
            .customizationID("search")
            #if os(tvOS)
            // Profil als Symbol rechts in der Tab-Leiste (Brandguide S. 9); öffnet Quellen und Einstellungen.
            Tab(value: MainTab.settings) {
                SettingsView(settings: settings, session: session, appModel: appModel, backup: backup)
            } label: {
                Label("Profil und Einstellungen", systemImage: "person.crop.circle.fill")
                    .labelStyle(.iconOnly)
            }
            #else
            // Wie in der Apple-TV-App: Einstellungen sind kein Tab (die Tab-Leiste bleibt ohne «Mehr»), sondern öffnen
            // sich aus dem Fuss der Seitenleiste (iPad, Mac, ⌘,) oder dem Profil-Symbol oben rechts (iPhone).
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        // Das Menü liegt hinter dem Fernsehbild: ein Schritt zurück führt wieder ins Fernsehen.
        .overlay(alignment: .bottomTrailing) { backToTV }
        #if os(tvOS)
        .onExitCommand { Task { await session.live.resumeLastChannel() } }
        #endif
        #if !os(tvOS)
        .tabViewCustomization($customization)
        .tabViewSidebarHeader { SidebarHeader() }
        .tabViewSidebarBottomBar {
            SidebarFooter(profile: session.profile, expiry: session.live.accountExpiry, isSelected: showsSettings) { showsSettings = true }
        }
        .modifier(LiquidGlassTabBar(session: session))
        #endif
        #if os(tvOS)
        .overlay(alignment: .topLeading) {
            // Marke oben links in der Safe Area (Brandguide/HIG: 80 pt seitlich, 60 pt oben).
            Image("IPTelevisionLockup")
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .padding(.leading, Theme.Layout.safeX)
                .padding(.top, Theme.Layout.safeY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #endif
        // Eine einzige Vollbild-Anzeige für Live-Bild, Film/Serie und Multiview: mehrere Cover an derselben Ansicht
        // (oder in einem Hintergrund der Seitenleisten-Tabs) öffnen sich nicht zuverlässig. Die Player liegen hier
        // statt in den Tabs, damit auch die Suche sie öffnen kann.
        .playerCover(isPresented: Binding(
            get: { session.multiview.isPresented || session.live.isPlayerPresented || session.vodPlayer.isPresented },
            set: { isPresented in
                guard !isPresented else { return }
                if session.multiview.isPresented { session.multiview.closeAll() }
                if session.live.isPlayerPresented { session.live.closePlayer() }
                if session.vodPlayer.isPresented { session.vodPlayer.close() }
            }
        )) {
            Group {
                if session.multiview.isPresented {
                    MultiviewScreen(model: session.multiview, live: session.live)
                } else if session.live.isPlayerPresented {
                    PlayerScreen(model: session.live)
                } else {
                    VODPlayerScreen(model: session.vodPlayer)
                }
            }
            // Die Player haben einen schwarzen Hintergrund: im hellen Erscheinungsbild wären Text und Symbole darauf unsichtbar.
            .preferredColorScheme(.dark)
            // Auf dem Mac liegt der Player als Ebene im Fenster: dort gilt das Erscheinungsbild des Fensters, also hier erzwingen.
            .environment(\.colorScheme, .dark)
            .sessionEnvironment(session, settings: settings, backdrop: backdrop)
        }
        .sheet(isPresented: Bindable(session.parental).isPromptingPIN) {
            PINPromptView(
                parental: session.parental, mode: .unlock, title: String(localized: "PIN eingeben"),
                onSuccess: {}, onCancel: { session.parental.isPromptingPIN = false }
            )
            .sessionEnvironment(session, settings: settings, backdrop: backdrop)
        }
        #if !os(tvOS)
        .environment(\.openSettingsSheet, SettingsOpener { showsSettings = true })
        .sheet(isPresented: $showsSettings) {
            VStack(spacing: 0) {
                SettingsView(settings: settings, session: session, appModel: appModel, backup: backup)
                HStack {
                    Spacer()
                    Button("Fertig") { showsSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
            #if os(macOS)
            .fitsInMainWindow(width: 760, height: 760)
            #endif
            .sessionEnvironment(session, settings: settings, backdrop: backdrop)
        }
        #endif
        .sheet(item: $editorPage) { page in
            ListEditorView(settings: settings, session: session, page: page, onClose: { editorPage = nil })
                .sessionEnvironment(session, settings: settings, backdrop: backdrop)
        }
        .environment(\.openListEditor, ListEditorOpener { editorPage = $0 })
        .sessionEnvironment(session, settings: settings, backdrop: backdrop)
        .organizationSheets(session.organization)
    }
}

extension View {
    /// Gibt Vollbild-Anzeigen und Fenstern dieselben Umgebungswerte wie dem Rest der App.
    /// Presentations erben die Umgebung nicht zuverlässig von weiter aussen gesetzten Modifiern; fehlt ein Wert,
    /// stürzt die Ansicht beim Öffnen ab.
    func sessionEnvironment(_ session: ProfileSession, settings: SettingsModel, backdrop: BackdropState) -> some View {
        environment(backdrop)
            .environment(settings)
            .environment(session.parental)
            .environment(session.organization)
            .environment(session.multiview)
            .environment(\.displayTimeZone, settings.settings.timeZone)
            .environment(\.channelTileStyle, ChannelTileStyle(showsNames: settings.settings.showsChannelNames, size: settings.settings.tileSize))
            .tint(Theme.focusBackground)
            #if os(macOS)
            // Blätter erben den Formular-Stil aus `RootView` nicht: ohne ihn stehen Einstellungen als lose Liste da.
            .formStyle(.grouped)
            #endif
    }
}
