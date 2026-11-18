import ARJOCore
import ARJONetwork
import Foundation
import Observation

@MainActor
@Observable
public final class LoginViewModel {
    public enum Mode: String, CaseIterable, Identifiable {
        case xtream
        case playlist

        public var id: Self { self }
        public var title: String { self == .xtream ? "Xtream" : "M3U-Playlist" }
    }

    public enum State: Equatable {
        case idle
        case loading
        case failed(String)
        case succeeded(Profile)
    }

    public var mode: Mode = .xtream
    public var server = ""
    public var username = ""
    public var password = ""
    public var playlistURL = ""
    public var sourceName = ""
    public private(set) var state: State = .idle

    private let makeClient: (XtreamCredentials) -> any XtreamAuthenticating
    private let credentialStore: any CredentialStore
    private let profileRepository: any ProfileRepository
    private let validatePlaylist: (URL) async throws -> Void
    private let importPlaylistFile: ((URL) throws -> URL)?
    private let onSignedIn: (Profile) -> Void

    /// - Parameters:
    ///   - validatePlaylist: Prüft, dass die Adresse eine M3U-Playlist liefert (wirft sonst).
    ///   - importPlaylistFile: Kopiert eine gewählte Datei in den App-Speicher und liefert deren dauerhaften Pfad;
    ///     `nil`, wo es keine Dateiauswahl gibt (Apple TV).
    public init(
        makeClient: @escaping (XtreamCredentials) -> any XtreamAuthenticating,
        credentialStore: any CredentialStore,
        profileRepository: any ProfileRepository,
        validatePlaylist: @escaping (URL) async throws -> Void = { _ in },
        importPlaylistFile: ((URL) throws -> URL)? = nil,
        onSignedIn: @escaping (Profile) -> Void = { _ in }
    ) {
        self.makeClient = makeClient
        self.credentialStore = credentialStore
        self.profileRepository = profileRepository
        self.validatePlaylist = validatePlaylist
        self.importPlaylistFile = importPlaylistFile
        self.onSignedIn = onSignedIn
    }

    public var supportsFileImport: Bool { importPlaylistFile != nil }

    public var canSubmit: Bool {
        guard state != .loading else { return false }
        switch mode {
        case .xtream:
            return !server.trimmed.isEmpty && !username.trimmed.isEmpty && !password.isEmpty
        case .playlist:
            return !playlistURL.trimmed.isEmpty
        }
    }

    public func reset() {
        mode = .xtream
        server = ""
        username = ""
        password = ""
        playlistURL = ""
        sourceName = ""
        state = .idle
    }

    public func signIn() async {
        guard canSubmit else { return }
        state = .loading
        do {
            switch mode {
            case .xtream: try await signInXtream()
            case .playlist: try await signInPlaylist(url: try Self.playlistURL(from: playlistURL))
            }
        } catch let error as LocalizedError {
            state = .failed(error.errorDescription ?? String(localized: "Anmeldung fehlgeschlagen."))
        } catch {
            state = .failed(String(localized: "Anmeldung fehlgeschlagen."))
        }
    }

    /// Übernimmt eine auf dem Gerät gewählte M3U-Datei.
    public func signIn(withPlaylistFile file: URL) async {
        guard state != .loading, let importPlaylistFile else { return }
        state = .loading
        do {
            try await signInPlaylist(url: try importPlaylistFile(file), fallbackName: file.deletingPathExtension().lastPathComponent)
        } catch let error as LocalizedError {
            state = .failed(error.errorDescription ?? String(localized: "Die Datei konnte nicht gelesen werden."))
        } catch {
            state = .failed(String(localized: "Die Datei konnte nicht gelesen werden."))
        }
    }

    private func signInXtream() async throws {
        let credentials = XtreamCredentials(
            serverURL: try XtreamServerURL.normalize(server),
            username: username.trimmed,
            password: password
        )
        _ = try await makeClient(credentials).authenticate()
        let profile = await profile(for: .xtream(credentials), name: credentials.serverURL.host() ?? "Xtream", kind: .xtream)
        guard await persist(.xtream(credentials), as: profile) else { return }
        password = ""
        finish(profile)
    }

    private func signInPlaylist(url: URL, fallbackName: String? = nil) async throws {
        try await validatePlaylist(url)
        let name = sourceName.trimmed.isEmpty ? (fallbackName ?? url.host() ?? "Playlist") : sourceName.trimmed
        let profile = await profile(for: .m3uURL(url), name: name, kind: .m3u)
        guard await persist(.m3uURL(url), as: profile) else { return }
        finish(profile)
    }

    /// Dieselbe Quelle (z. B. schon auf einem anderen Gerät angemeldet und per iCloud übertragen) bekommt kein zweites
    /// Profil, damit Wiedergabestand, Favoriten und letzter Sender geräteübergreifend zusammenbleiben.
    private func profile(for credentials: SourceCredentials, name: String, kind: ProfileKind) async -> Profile {
        let fingerprint = SourceFingerprint.make(for: credentials)
        if let existing = try? await profileRepository.profiles().first(where: { $0.sourceFingerprint == fingerprint && $0.kind == kind }) {
            return existing
        }
        return Profile(name: name, kind: kind, sourceFingerprint: fingerprint)
    }

    /// Speichert zuerst die Zugangsdaten, dann das Profil; schlägt Letzteres fehl, werden die Zugangsdaten wieder entfernt.
    private func persist(_ credentials: SourceCredentials, as profile: Profile) async -> Bool {
        do {
            try credentialStore.save(credentials, for: profile.id)
        } catch {
            state = .failed(String(localized: "Die Zugangsdaten konnten nicht sicher gespeichert werden."))
            return false
        }
        do {
            try await profileRepository.save(profile)
        } catch {
            // Aufräumen ist best effort: ein übrig gebliebener Eintrag ist ohne Profil unerreichbar.
            try? credentialStore.delete(for: profile.id)
            state = .failed(String(localized: "Das Profil konnte nicht gespeichert werden."))
            return false
        }
        return true
    }

    private func finish(_ profile: Profile) {
        state = .succeeded(profile)
        onSignedIn(profile)
    }

    /// Akzeptiert auch Adressen ohne Schema (dann `http`), verlangt aber Host und `http`/`https`.
    static func playlistURL(from input: String) throws -> URL {
        let trimmed = input.trimmed
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host(), !host.isEmpty
        else { throw PlaylistAddressError.invalid }
        return url
    }
}

enum PlaylistAddressError: Error, LocalizedError {
    case invalid

    var errorDescription: String? { String(localized: "Die Playlist-Adresse ist ungültig.") }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
