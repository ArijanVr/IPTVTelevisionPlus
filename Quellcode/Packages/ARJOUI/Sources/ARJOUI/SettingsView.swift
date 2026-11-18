import ARJOCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: SettingsModel
    @Environment(UpdateChecker.self) private var updates: UpdateChecker?
    let session: ProfileSession
    let appModel: AppModel
    let backup: BackupService
    #if !os(tvOS)
    @State private var backupFile: BackupFile?
    @State private var isImporting = false
    #endif
    @State private var backupMessage: String?
    @State private var profileToRemove: Profile?
    @State private var confirmsClearing = false
    @State private var isClearing = false
    @State private var clearError: String?

    private static let timeZones = [
        "Europe/Zurich", "Europe/Berlin", "Europe/London", "Europe/Lisbon", "Europe/Athens", "Europe/Istanbul",
        "Europe/Moscow", "Asia/Dubai", "Asia/Kolkata", "Asia/Tokyo", "Australia/Sydney",
        "America/New_York", "America/Chicago", "America/Los_Angeles", "UTC",
    ]

    private static var bufferTitles: [Double: String] {
        [
            1.5: String(localized: "Klein (1,5 s)"), 4: String(localized: "Normal (4 s)"),
            8: String(localized: "Gross (8 s)"), 15: String(localized: "Sehr gross (15 s)"),
        ]
    }

    var body: some View {
        NavigationStack {
            SettingsHub(tiles: tiles)
                .navigationTitle("Einstellungen")
        }
        .confirmationDialog("Lokale Daten löschen?", isPresented: $confirmsClearing, titleVisibility: .visible) {
            Button("Löschen und neu laden", role: .destructive) { clearCaches() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Senderlisten, Filme, Serien, Programmführer und Bilder werden gelöscht und neu geladen. Zugangsdaten, Favoriten und Wiedergabestand bleiben erhalten.")
        }
        .confirmationDialog(
            "Quelle entfernen?",
            isPresented: Binding(get: { profileToRemove != nil }, set: { if !$0 { profileToRemove = nil } }),
            titleVisibility: .visible,
            presenting: profileToRemove
        ) { profile in
            Button("«\(profile.name)» entfernen", role: .destructive) { Task { await appModel.signOut(profile) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Zugangsdaten, Listen und Wiedergabestand dieser Quelle werden von diesem Gerät gelöscht.")
        }
        .alert(
            "Einstellungen",
            isPresented: Binding(get: { settings.errorMessage != nil }, set: { if !$0 { settings.dismissError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(settings.errorMessage ?? "")
        }
        #if !os(tvOS)
        .fileExporter(
            isPresented: Binding(get: { backupFile != nil }, set: { if !$0 { backupFile = nil } }),
            document: backupFile,
            contentType: .json,
            defaultFilename: "IPTelevision+-Backup"
        ) { result in
            if case .failure = result { backupMessage = String(localized: "Das Backup konnte nicht gespeichert werden.") }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            Task { await restore(result) }
        }
        #endif
        .alert(
            "Backup",
            isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupMessage ?? "")
        }
        .alert(
            "Löschen fehlgeschlagen",
            isPresented: Binding(get: { clearError != nil }, set: { if !$0 { clearError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clearError ?? "")
        }
    }

    /// Kacheln der Startseite der Einstellungen (Brandguide: Graphite-Karten, Icon links, Titel und Untertitel).
    private var tiles: [SettingsTileModel] {
        [
            SettingsTileModel(icon: "antenna.radiowaves.left.and.right", title: "Quellen", subtitle: "Playlists, wechseln, entfernen") {
                Form { sourcesSection }.navigationTitle("Quellen")
            },
            SettingsTileModel(icon: "list.bullet", title: "Listen & Ordner", subtitle: "Startseite, Favoriten, Kanalnummern") {
                Form { listsSection }.navigationTitle("Listen & Ordner")
            },
            SettingsTileModel(icon: "lock", title: "Kindersicherung", subtitle: "PIN, gesperrte Kategorien") {
                Form { parentalSection }.navigationTitle("Kindersicherung")
            },
            SettingsTileModel(icon: "circle.lefthalf.filled", title: "Darstellung", subtitle: "Kachelgrösse, Sendernamen, Sprache") {
                Form { appearanceSection }.navigationTitle("Darstellung")
            },
            SettingsTileModel(icon: "play", title: "Wiedergabe", subtitle: "Seitenverhältnis, Puffer, Start") {
                Form { playbackSection }.navigationTitle("Wiedergabe")
            },
            SettingsTileModel(icon: "calendar", title: "Programmführer", subtitle: "Zeitversatz, Zeitzone") {
                Form { guideSection }.navigationTitle("Programmführer")
            },
            SettingsTileModel(icon: "externaldrive", title: "Daten", subtitle: "Aktualisieren, Cache leeren") {
                Form { dataSection }.navigationTitle("Daten")
            },
            SettingsTileModel(icon: "icloud", title: "iCloud-Sync", subtitle: "Geräte abgleichen") {
                Form { SyncSettingsSection(sync: session.sync) { await session.clearHistory() } }.navigationTitle("iCloud-Sync")
            },
            SettingsTileModel(icon: "arrow.down.doc", title: "Backup", subtitle: "Exportieren, wiederherstellen") {
                Form { backupSection }.navigationTitle("Backup")
            },
            SettingsTileModel(icon: "info.circle", title: "Über IP Television+", subtitle: "Version, Lizenzen, ARJO LAB") {
                Form { aboutSection }.navigationTitle("Über IP Television+")
            },
        ]
    }

    private var listsSection: some View {
        Section {
            NavigationLink("Meine Listen und Startseite") {
                ListEditorView(settings: settings, session: session, page: .categories)
            }
            NavigationLink("Favoriten & Ordner") {
                OrganizationSettingsView(
                    organization: session.organization,
                    groups: [.live: session.live.groups, .movie: session.movies.groups, .series: session.series.groups]
                )
            }
            NavigationLink("Kanalnummern") {
                ChannelNumbersView(live: session.live, organization: session.organization)
            }
        }
    }

    private var parentalSection: some View {
        Section {
            NavigationLink("Kindersicherung") {
                ParentalSettingsView(parental: session.parental, session: session)
            }
        } footer: {
            Text(LocalizedStringKey(session.parental.hasPIN ? "Kindersicherung ist aktiv." : "Mit einer PIN lassen sich Kategorien sperren."))
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(appModel.profiles) { profile in
                Button {
                    appModel.switchTo(profile)
                } label: {
                    HStack {
                        Text(profile.name)
                        Spacer()
                        if profile.id == session.profile.id { Image(systemName: "checkmark") }
                    }
                }
                .contextMenu {
                    Button("Entfernen", role: .destructive) { profileToRemove = profile }
                }
            }
            Button("Quelle hinzufügen") { appModel.beginAddingProfile() }
            if appModel.profiles.count > 1 {
                Button("Aktive Quelle entfernen", role: .destructive) { profileToRemove = session.profile }
            }
        } header: {
            Text("Quellen")
        } footer: {
            Text("Tippe auf eine Quelle, um zu ihr zu wechseln.")
        }
    }

    private var appearanceSection: some View {
        Section("Darstellung") {
            // Hell/Dunkel folgt dem System, Farben sind fix (Brandguide S. 14 und 16): keine eigene Wahl in der App.
            Toggle("Sendernamen unter den Kacheln", isOn: $settings.settings.showsChannelNames)
            Picker("Kachelgrösse", selection: $settings.settings.tileSize) {
                ForEach(TileSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            LabeledContent("Sprache", value: Self.currentLanguageName)
        }
    }

    private var playbackSection: some View {
        Section("Wiedergabe") {
            Picker("Seitenverhältnis", selection: $settings.settings.aspect) {
                ForEach(AspectMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Puffer", selection: $settings.settings.bufferSeconds) {
                ForEach(bufferChoices, id: \.self) { Text(Self.bufferTitles[$0] ?? "\($0) s").tag($0) }
            }
            Picker("Beim Start", selection: $settings.settings.resumeLastChannelOnLaunch) {
                Text("Kanal 1").tag(false)
                Text("Zuletzt gesehener Kanal").tag(true)
            }
            Toggle("Nächste Episode automatisch abspielen", isOn: $settings.settings.autoPlayNextEpisode)
            #if os(tvOS)
            Toggle("«Weiterschauen» im Top Shelf", isOn: $settings.settings.topShelfEnabled)
            #endif
        }
    }

    private var guideSection: some View {
        Section {
            Picker("EPG-Zeitversatz", selection: $settings.settings.epgOffsetMinutes) {
                ForEach(offsetChoices, id: \.self) { Text(Self.offsetTitle($0)).tag($0) }
            }
            Picker("Zeitzone", selection: Binding(
                get: { settings.settings.timeZoneID ?? "" },
                set: { settings.settings.timeZoneID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Gerät (\(TimeZone.current.identifier))").tag("")
                ForEach(timeZoneChoices, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
            }
        } header: {
            Text("Programmführer")
        } footer: {
            Text("Der Zeitversatz verschiebt alle Sendezeiten, falls dein Anbieter in einer anderen Zeitzone sendet.")
        }
    }

    private var dataSection: some View {
        Section("Daten") {
            Toggle("Listen automatisch aktualisieren", isOn: $settings.settings.autoRefresh)
            Button(role: .destructive) {
                confirmsClearing = true
            } label: {
                if isClearing { ProgressView() } else { Text("Cache leeren") }
            }
            .disabled(isClearing)
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        #if os(tvOS)
        Section {
            EmptyView()
        } header: {
            Text("Backup")
        } footer: {
            Text("Ein Backup als Datei erstellst du auf iPhone, iPad oder Mac.")
        }
        #else
        Section {
            Button("Backup exportieren …") { Task { await exportBackup() } }
            Button("Backup wiederherstellen …") { isImporting = true }
        } header: {
            Text("Backup")
        } footer: {
            Text("Das Backup enthält Einstellungen, Favoriten, Ordner und Wiedergabestand, aber keine Zugangsdaten und keine PIN. Speichere die Datei z. B. in iCloud Drive.")
        }
        #endif
    }

    #if !os(tvOS)
    private func exportBackup() async {
        do {
            backupFile = BackupFile(data: try await backup.makeBackup())
        } catch {
            backupMessage = String(localized: "Das Backup konnte nicht erstellt werden.")
        }
    }

    private func restore(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let summary = try await backup.restore(from: try Data(contentsOf: url))
            await session.organization.load()
            var message = String(localized: "Wiederhergestellt für: \(summary.restoredProfiles.joined(separator: ", ")).")
            if summary.restoredProfiles.isEmpty { message = String(localized: "Keine passende Quelle gefunden.") }
            if !summary.skippedProfiles.isEmpty {
                message += String(localized: " Nicht übernommen (Quelle fehlt auf diesem Gerät): \(summary.skippedProfiles.joined(separator: ", ")).")
            }
            backupMessage = message
        } catch let error as BackupError {
            backupMessage = error.errorDescription
        } catch {
            backupMessage = String(localized: "Das Backup konnte nicht gelesen werden.")
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
            #if !os(macOS)
            if let updates { UpdateRow(checker: updates) }
            #endif
            ArjoLabSender()
        } header: {
            Text("Über IP Television+")
        } footer: {
            Text("IP Television+ ist nur ein Player und liefert keine Sender oder Inhalte mit. Du verwendest deine eigenen Zugangsdaten. Für Formate, die Apple nicht abspielt, nutzt die App VLCKit (LGPL 2.1, © VideoLAN).")
        }
    }

    private var bufferChoices: [Double] {
        AppSettings.bufferChoices.contains(settings.settings.bufferSeconds)
            ? AppSettings.bufferChoices
            : (AppSettings.bufferChoices + [settings.settings.bufferSeconds]).sorted()
    }

    private var offsetChoices: [Int] {
        var values = Array(stride(from: AppSettings.epgOffsetRangeMinutes.lowerBound, through: AppSettings.epgOffsetRangeMinutes.upperBound, by: 30))
        if !values.contains(settings.settings.epgOffsetMinutes) { values.append(settings.settings.epgOffsetMinutes) }
        return values.sorted()
    }

    private var timeZoneChoices: [String] {
        guard let current = settings.settings.timeZoneID, !Self.timeZones.contains(current) else { return Self.timeZones }
        return [current] + Self.timeZones
    }

    /// Sprache, in der die App gerade angezeigt wird.
    private static var currentLanguageName: String {
        let identifier = Bundle.main.preferredLocalizations.first ?? "de"
        return Locale.current.localizedString(forIdentifier: identifier)?.capitalized ?? identifier
    }

    private static func offsetTitle(_ minutes: Int) -> String {
        if minutes == 0 { return String(localized: "Kein Versatz") }
        let sign = minutes > 0 ? "+" : "−"
        let absolute = abs(minutes)
        return absolute % 60 == 0
            ? String(localized: "\(sign)\(absolute / 60) Std.")
            : String(localized: "\(sign)\(absolute / 60) Std. \(absolute % 60) Min.")
    }

    private func clearCaches() {
        isClearing = true
        Task {
            defer { isClearing = false }
            do {
                try await session.clearLocalData()
            } catch {
                clearError = String(localized: "Die lokalen Daten konnten nicht gelöscht werden.")
            }
        }
    }
}
