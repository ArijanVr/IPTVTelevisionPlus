import ARJOCore
import ARJOData
import ARJONetwork
import ARJOPlayer
import ARJOUI
import Foundation
import OSLog

/// Baut die konkreten Implementierungen zusammen; die Packages kennen sich nur über Protokolle.
@MainActor
struct AppEnvironment {
    let appModel: AppModel
    let settings: SettingsModel
    let backup: BackupService
    let loginModel: LoginViewModel
    let makeSession: (Profile) -> ProfileSession

    /// Gemeinsamer iCloud-Container aller Plattformen (iPhone, iPad, Apple TV, Mac).
    static let cloudKitContainer = "iCloud.ch.arjo.iptelevision"
    /// Version der Inhaltskennungen; 2 = `ContentIdentity` (ohne Zugangsdaten in Kennungen).
    private static let contentIDVersion = 2
    private static let contentIDVersionKey = "ch.arjo.iptelevision.contentIDVersion"

    init() throws {
        let credentialStore = KeychainCredentialStore()
        // Mit dem Kompilierflag ICLOUD_SYNC (und der iCloud-Berechtigung, siehe docs/ICLOUD-SYNC.md) gleicht CloudKit
        // die Nutzerdaten in der privaten Datenbank ab. Der Schalter in den Einstellungen wirkt beim nächsten Start.
        let sync: any SyncMonitoring
        #if ICLOUD_SYNC
        let syncEnabled = SyncPreference.launchValue
        let profiles = try SwiftDataProfileRepository(cloudKitContainer: syncEnabled ? Self.cloudKitContainer : nil)
        sync = syncEnabled ? CloudSyncMonitor(containerIdentifier: Self.cloudKitContainer) : StaticSyncMonitor(status: .disabled)
        #else
        let profiles = try SwiftDataProfileRepository()
        sync = StaticSyncMonitor(status: .unavailable)
        #endif
        let maintenance = profiles.makeMaintenance()
        let progress = profiles.makeProgressRepository()
        let catalog = try SwiftDataCatalogRepository()
        let epg = try SwiftDataEPGRepository()
        let vod = try SwiftDataVODRepository()
        let settings = SettingsModel(repository: profiles.makeSettingsRepository())
        let pinStore = KeychainPINStore()
        let organization = profiles.makeOrganizationRepository()
        self.settings = settings
        backup = BackupService(settings: settings, profiles: profiles, organization: organization, progress: progress)

        let appModel = AppModel(
            profiles: profiles,
            activeProfile: UserDefaultsActiveProfileStore(),
            credentialStore: credentialStore,
            cleanups: [
                { try await catalog.deleteCatalog(for: $0) },
                { try await epg.deleteEPG(for: $0) },
                { try await vod.deleteVOD(for: $0) },
                { try await progress.deleteProgress(for: $0) },
                { try await organization.deleteOrganization(for: $0) },
                { profileID in try Self.removeImportedPlaylist(of: profileID, credentialStore: credentialStore) },
            ],
            localCleanups: [
                { try await catalog.deleteCatalog(for: $0) },
                { try await epg.deleteEPG(for: $0) },
                { try await vod.deleteVOD(for: $0) },
            ],
            prepareData: {
                await Self.migrateContentIDs(maintenance: maintenance, profiles: profiles, catalog: catalog, vod: vod)
            },
            merging: ProfileMerging(
                planned: { try await maintenance.plannedMerges() },
                merge: { try await maintenance.mergeDuplicateProfiles() }
            )
        )
        self.appModel = appModel
        loginModel = LoginViewModel(
            makeClient: { XtreamClient(credentials: $0) },
            credentialStore: credentialStore,
            profileRepository: profiles,
            validatePlaylist: { _ = try await M3UStreamParser.readHeader(of: $0) },
            importPlaylistFile: Self.playlistImporter,
            onSignedIn: { appModel.signedIn($0) }
        )
        makeSession = { profile in
            let liveEngine = HybridPlaybackEngine.makeDefault()
            let vodEngine = HybridPlaybackEngine.makeDefault()
            @MainActor func vodCatalog(_ kind: VODKind) -> VODCatalogModel {
                VODCatalogModel(
                    kind: kind, profile: profile, repository: vod, credentialStore: credentialStore,
                    makeProvider: { XtreamClient(credentials: $0) },
                    refreshesAutomatically: { settings.settings.autoRefresh },
                    makePlaylistProvider: { M3UVODProvider(url: $0) }
                )
            }
            let parental = ParentalControl(profileID: profile.id, settings: settings, pinStore: pinStore)
            return ProfileSession(
                profile: profile,
                live: LiveTVViewModel(
                    profile: profile,
                    catalog: catalog,
                    profiles: profiles,
                    credentialStore: credentialStore,
                    makeProvider: { XtreamClient(credentials: $0) },
                    playback: PlaybackController(engine: liveEngine, zapDebounce: 0.4),
                    engine: liveEngine,
                    epg: EPGModel(
                        profile: profile,
                        epg: epg,
                        catalog: catalog,
                        credentialStore: credentialStore,
                        makeProvider: { XtreamEPGProvider(credentials: $0) },
                        epgOffset: { settings.settings.epgOffset },
                        makePlaylistProvider: { M3UPlaylistSource(url: $0) }
                    ),
                    resumesOnLaunch: { settings.settings.resumeLastChannelOnLaunch },
                    refreshesAutomatically: { settings.settings.autoRefresh },
                    makePlaylistSource: { M3UPlaylistSource(url: $0) },
                    serverTimeZone: Self.serverTimeZone,
                    accountInfo: Self.accountInfo
                ),
                movies: vodCatalog(.movie),
                series: vodCatalog(.series),
                vodPlayer: VODPlayerModel(
                    profile: profile,
                    credentialStore: credentialStore,
                    progress: progress,
                    playback: PlaybackController(engine: vodEngine),
                    engine: vodEngine,
                    autoPlayNextEpisode: { settings.settings.autoPlayNextEpisode },
                    resolveDirectURL: { await Self.playlistURL(of: $0, profileID: profile.id, vod: vod) }
                ),
                home: HomeModel(
                    profile: profile,
                    progress: progress,
                    topShelf: TopShelfStore.appGroup(),
                    isEnabled: { settings.settings.topShelfEnabled },
                    isPublishable: { progress in
                        !parental.isMarkedLocked(progress.target.kind == .movie ? .movie : .series, progress.target.groupName ?? "")
                    },
                    vod: vod
                ),
                search: SearchModel(
                    profile: profile, catalog: catalog, vod: vod, epg: epg,
                    epgOffset: { settings.settings.epgOffset },
                    isLocked: { parental.isLocked($0, $1) },
                    history: .standard
                ),
                parental: parental,
                organization: OrganizationModel(profile: profile, repository: organization, catalog: catalog),
                multiview: MultiviewModel(profile: profile, credentialStore: credentialStore, makeEngine: { HybridPlaybackEngine.makeDefault() }),
                sync: sync,
                clearData: { profileID in
                    try await catalog.deleteCatalog(for: profileID)
                    try await epg.deleteEPG(for: profileID)
                    try await vod.deleteVOD(for: profileID)
                }
            )
        }
    }

    // MARK: Inhaltskennungen und Playlist-Adressen

    /// Stream-Adresse eines Films oder einer Episode aus dem lokalen Playlist-Katalog. Der synchronisierte
    /// Wiedergabestand enthält sie nicht, weil sie Zugangsdaten enthalten kann.
    private static func playlistURL(of target: PlaybackTarget, profileID: UUID, vod: SwiftDataVODRepository) async -> URL? {
        do {
            switch target.kind {
            case .movie:
                return try await vod.item(for: profileID, kind: .movie, sourceID: target.streamID)?.streamURL
            case .episode:
                guard let seriesID = target.seriesID,
                      let series = try await vod.item(for: profileID, kind: .series, sourceID: seriesID) else { return nil }
                return series.seasons?.lazy.flatMap(\.episodes).first { $0.id == target.streamID }?.streamURL
            }
        } catch {
            Logger(subsystem: "ch.arjo.iptelevision", category: "vod").error("Playlist-Adresse nicht gefunden: \(error.localizedDescription)")
            return nil
        }
    }

    /// Stellt Kennungen älterer Versionen um (läuft bei jedem Start, ist idempotent). Beim ersten Start mit neuen
    /// Kennungen werden die Playlist-Kataloge neu geladen, damit sie zu den umgestellten Nutzerdaten passen.
    private static func migrateContentIDs(
        maintenance: UserDataMaintenance, profiles: SwiftDataProfileRepository,
        catalog: SwiftDataCatalogRepository, vod: SwiftDataVODRepository
    ) async {
        let log = Logger(subsystem: "ch.arjo.iptelevision", category: "migration")
        do {
            try await maintenance.migrateLegacyContentIDs()
            let defaults = UserDefaults.standard
            guard defaults.integer(forKey: contentIDVersionKey) < contentIDVersion else { return }
            for profile in try await profiles.profiles() where profile.kind == .m3u {
                try await catalog.deleteCatalog(for: profile.id)
                try await vod.deleteVOD(for: profile.id)
            }
            defaults.set(contentIDVersion, forKey: contentIDVersionKey)
        } catch {
            log.error("Migration der Kennungen fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: Catch-up

    /// Zeitzone des Xtream-Servers: Timeshift-Adressen brauchen die Uhrzeit des Servers.
    private static func serverTimeZone(for credentials: XtreamCredentials) async -> TimeZone? {
        do {
            let info = try await XtreamClient(credentials: credentials).authenticate()
            return info.serverTimeZone.flatMap(TimeZone.init(identifier:))
        } catch {
            Logger(subsystem: "ch.arjo.iptelevision", category: "catchup").error("Server-Zeitzone unbekannt: \(error.localizedDescription)")
            return nil
        }
    }

    /// Kontoinformationen (Status, Ablaufdatum); `nil`, wenn der Anbieter nicht antwortet.
    private static func accountInfo(for credentials: XtreamCredentials) async -> XtreamAccountInfo? {
        try? await XtreamClient(credentials: credentials).authenticate()
    }

    // MARK: M3U-Dateien

    /// Auf Apple TV gibt es keine Dateiauswahl.
    private static var playlistImporter: ((URL) throws -> URL)? {
        #if os(tvOS)
        nil
        #else
        { source in
            let directory = try playlistDirectory()
            let target = directory.appendingPathComponent("\(UUID().uuidString).m3u")
            try FileManager.default.copyItem(at: source, to: target)
            return target
        }
        #endif
    }

    private static func playlistDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Playlists", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Löscht die kopierte Playlist-Datei, wenn eine Quelle entfernt wird.
    private static func removeImportedPlaylist(of profileID: UUID, credentialStore: KeychainCredentialStore) throws {
        guard case .m3uURL(let url)? = try credentialStore.load(for: profileID), url.isFileURL,
              url.deletingLastPathComponent().lastPathComponent == "Playlists"
        else { return }
        try FileManager.default.removeItem(at: url)
    }
}
