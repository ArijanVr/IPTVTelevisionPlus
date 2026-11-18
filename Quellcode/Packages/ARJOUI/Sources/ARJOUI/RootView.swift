import ARJOCore
import SwiftUI

public struct RootView: View {
    @Bindable private var model: AppModel
    @Bindable private var settings: SettingsModel
    @Environment(\.scenePhase) private var scenePhase
    private let loginModel: LoginViewModel
    private let makeSession: (Profile) -> ProfileSession
    private let backup: BackupService

    public init(
        model: AppModel,
        settings: SettingsModel,
        loginModel: LoginViewModel,
        backup: BackupService,
        makeSession: @escaping (Profile) -> ProfileSession
    ) {
        self.backup = backup
        self.model = model
        self.settings = settings
        self.loginModel = loginModel
        self.makeSession = makeSession
    }

    public var body: some View {
        ZStack {
            ThemeBackground()
            switch model.phase {
            case .launching:
                ProgressView()
            case .needsLogin:
                LoginView(model: loginModel, onCancel: model.canCancelLogin ? { model.cancelLogin() } : nil)
                    .onAppear { loginModel.reset() }
                    #if DEBUG
                    // Nur Debug: `-ARJOSeedM3U <url>` als Startargument meldet die Playlist an (Screenshots im Simulator ohne Tastatur).
                    .task {
                        guard let seed = UserDefaults.standard.string(forKey: "ARJOSeedM3U"), !seed.isEmpty else { return }
                        loginModel.mode = .playlist
                        loginModel.playlistURL = seed
                        await loginModel.signIn()
                    }
                    #endif
            case .live(let profile):
                SessionContainer(profile: profile, settings: settings, appModel: model, backup: backup, make: makeSession)
                .id(profile.id)
            case .failed(let message):
                VStack(spacing: 24) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Erneut versuchen") { Task { await model.bootstrap() } }
                }
                .padding(40)
            }
        }
        // Brandguide: Steuerelemente monochrom, Hell/Dunkel folgt dem System (keine eigene Einstellung).
        .tint(Theme.focusBackground)
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .environment(\.displayTimeZone, settings.settings.timeZone)
        .task {
            await settings.load()
            await model.bootstrap()
        }
        .onOpenURL { model.open($0) }
        // Änderungen anderer Geräte (iCloud) sichtbar machen, sobald die App wieder aktiv wird.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await settings.load()
                await model.refreshProfiles()
            }
        }
        .alert(
            "Fehler",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct SessionContainer: View {
    @State private var session: ProfileSession
    @Environment(\.scenePhase) private var scenePhase
    let settings: SettingsModel
    let appModel: AppModel
    let backup: BackupService

    init(profile: Profile, settings: SettingsModel, appModel: AppModel, backup: BackupService, make: (Profile) -> ProfileSession) {
        _session = State(initialValue: make(profile))
        self.settings = settings
        self.appModel = appModel
        self.backup = backup
    }

    var body: some View {
        MainTabView(session: session, settings: settings, appModel: appModel, backup: backup)
            .task {
                session.apply(settings.settings)
                await session.start()
            }
            .onChange(of: settings.settings) { _, new in session.apply(new) }
            .task(id: appModel.pendingDeepLink) {
                guard let url = appModel.pendingDeepLink else { return }
                appModel.consumeDeepLink()
                await session.handle(url)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    // Hintergrund oder Unterbrechung: Wiedergabestand nicht erst im nächsten Intervall sichern.
                    session.persistPending()
                    return
                }
                Task {
                    await session.sync.refresh()
                    await session.reloadUserData()
                }
            }
            .task {
                // Änderungen anderer Geräte sofort zeigen (Weiterschauen, Favoriten, letzter Sender, Quellen).
                for await _ in session.sync.remoteChanges() {
                    await settings.load()
                    await appModel.refreshProfiles()
                    await session.reloadUserData()
                }
            }
    }
}
