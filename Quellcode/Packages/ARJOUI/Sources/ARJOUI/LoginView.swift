import ARJOCore
import SwiftUI
import UniformTypeIdentifiers

public struct LoginView: View {
    @Bindable private var model: LoginViewModel
    @State private var isChoosingFile = false
    private let onCancel: (() -> Void)?

    /// - Parameter onCancel: Wird nur übergeben, wenn es schon ein Profil gibt.
    public init(model: LoginViewModel, onCancel: (() -> Void)? = nil) {
        self.model = model
        self.onCancel = onCancel
    }

    #if !os(tvOS)
    private static let playlistTypes: [UTType] = [
        UTType(filenameExtension: "m3u") ?? .plainText, UTType(filenameExtension: "m3u8") ?? .plainText, .plainText,
    ]
    #endif

    public var body: some View {
        ZStack {
            ThemeBackground()
            VStack(spacing: 28) {
                Image("IPTelevisionLockup")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .accessibilityLabel("IP Television+")

                if case .succeeded = model.state {
                    ProgressView()
                } else {
                    form
                }
            }
            .frame(maxWidth: 700)
            .padding(32)
        }
    }

    private var form: some View {
        VStack(spacing: 20) {
            Picker("Quelle", selection: $model.mode) {
                ForEach(LoginViewModel.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch model.mode {
            case .xtream: xtreamFields
            case .playlist: playlistFields
            }

            if case .failed(let message) = model.state {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await model.signIn() }
            } label: {
                if model.state == .loading {
                    ProgressView()
                } else {
                    Text("Anmelden").frame(maxWidth: .infinity)
                }
            }
            #if !os(tvOS)
            .buttonStyle(PrimaryButtonStyle())
            #endif
            .disabled(!model.canSubmit)

            #if !os(tvOS)
            if model.mode == .playlist, model.supportsFileImport {
                Button("M3U-Datei wählen …") { isChoosingFile = true }
            }
            #endif

            if let onCancel {
                Button("Abbrechen", action: onCancel)
            }
        }
        #if !os(tvOS)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.playlistTypes) { result in
            guard case .success(let url) = result else { return }
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                await model.signIn(withPlaylistFile: url)
            }
        }
        #endif
    }

    @ViewBuilder
    private var xtreamFields: some View {
        Text("Mit Xtream-Zugangsdaten anmelden").foregroundStyle(.secondary)
        TextField("Server", text: $model.server, prompt: Text(verbatim: String(localized: "Server (z. B. http://beispiel.ch:8080)")))
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .brandField()
        TextField("Benutzername", text: $model.username)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .brandField()
        SecureField("Passwort", text: $model.password)
            .brandField()
    }

    @ViewBuilder
    private var playlistFields: some View {
        Text("Adresse deiner M3U-Playlist").foregroundStyle(.secondary)
        TextField("Playlist-Adresse (http://…)", text: $model.playlistURL)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .brandField()
        TextField("Name (optional)", text: $model.sourceName)
            .brandField()
    }
}
