import ARJOPlayer
import ARJOUI
import OSLog
import SwiftUI
#if os(macOS)
import ARJOUpdate
#endif

@main
struct ARJOTVApp: App {
    private let environment: Result<AppEnvironment, Error>
    @State private var showsIntro = true
    #if os(macOS)
    // Sparkle: prüft laut Info.plist (SUFeedURL) täglich auf neue Releases in der öffentlichen Ablage.
    private let updater = AppUpdater()
    #else
    @State private var updates = UpdateChecker()
    @State private var showsUpdate = false
    @Environment(\.openURL) private var openURL
    #endif

    init() {
        BrandFonts.register()
        do {
            try AVPlayerEngine.configureAudioSession()
        } catch {
            Logger(subsystem: "ch.arjo.iptelevision", category: "app").error("Audio-Session: \(error.localizedDescription)")
        }
        environment = Result { try AppEnvironment() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch environment {
                case .success(let environment):
                    RootView(
                        model: environment.appModel,
                        settings: environment.settings,
                        loginModel: environment.loginModel,
                        backup: environment.backup,
                        makeSession: environment.makeSession
                    )
                case .failure(let error):
                    Text("Der Speicher konnte nicht geöffnet werden: \(error.localizedDescription)")
                        .padding(40)
                }
            }
            .overlay {
                if showsIntro {
                    IntroView { withAnimation(.easeOut(duration: 0.4)) { showsIntro = false } }
                        .transition(.opacity)
                }
            }
            #if os(macOS)
            // Mindestgrösse: Nach dem Verlassen des Players (Vollbild) springt das Fenster sonst auf eine winzige gespeicherte Grösse zurück.
            .frame(minWidth: 960, minHeight: 600)
            #else
            .environment(updates)
            .task { await updates.checkIfDue() }
            .onChange(of: updates.state) { _, state in
                if case .available = state { showsUpdate = true }
            }
            .alert("Update verfügbar", isPresented: $showsUpdate) {
                if case .available(let update) = updates.state {
                    #if !os(tvOS)
                    Button("Öffnen") { openURL(update.pageURL) }
                    #endif
                    Button("Später", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                if case .available(let update) = updates.state {
                    Text("Version \(update.version) liegt auf GitHub bereit. Installiere sie über TestFlight oder Xcode.")
                }
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") { updater.checkForUpdates() }
            }
        }
        #endif
    }
}
