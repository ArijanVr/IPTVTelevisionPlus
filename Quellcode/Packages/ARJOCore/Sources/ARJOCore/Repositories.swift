import Foundation

/// Lokaler, neu ladbarer Senderkatalog (wird nicht über iCloud synchronisiert).
public protocol CatalogRepository: Sendable {
    /// Ersetzt den Katalog des Profils erst, wenn der Strom vollständig gelesen wurde.
    /// Bricht der Import ab, bleibt der bisherige Katalog unverändert.
    func importChannels(for profileID: UUID, from channels: AsyncThrowingStream<Channel, Error>) async throws
    func groups(for profileID: UUID) async throws -> [ChannelGroup]
    func channels(for profileID: UUID, group: String, limit: Int) async throws -> [Channel]
    func channel(id: String, for profileID: UUID) async throws -> Channel?
    func deleteCatalog(for profileID: UUID) async throws
    /// Alle `tvg-id`/EPG-IDs des Katalogs, damit beim EPG-Import nur relevante Sendungen gespeichert werden.
    func epgChannelIDs(for profileID: UUID) async throws -> Set<String>
    /// Sender, deren Name `query` enthält (ohne Gross-/Kleinschreibung und Akzente), in Listenreihenfolge.
    func searchChannels(for profileID: UUID, query: String, limit: Int) async throws -> [Channel]
    /// Ordnet EPG-IDs dem ersten Sender mit dieser ID zu.
    func channels(forEPGIDs ids: [String], for profileID: UUID) async throws -> [String: Channel]
    /// Zeitpunkt des letzten vollständigen Imports; `nil`, wenn es keinen Katalog gibt.
    func lastUpdate(for profileID: UUID) async throws -> Date?
    /// Sender mit dieser festen Kanalnummer; `nil`, wenn es sie nicht gibt.
    func channel(number: Int, for profileID: UUID) async throws -> Channel?
    /// Sender mit der kleinsten Kanalnummer (Startkanal).
    func firstChannel(for profileID: UUID) async throws -> Channel?
    /// Gibt dem Sender eine neue Nummer. Ist sie vergeben, tauschen beide Sender ihre Nummern.
    func setNumber(_ number: Int, forChannelID id: String, for profileID: UUID) async throws
    /// Nummeriert alle Sender neu: Gruppen in dieser Reihenfolge (nicht genannte danach), in der Gruppe nach bisheriger Nummer, ab 1.
    func renumberByGroups(_ groupOrder: [String], for profileID: UUID) async throws
}

public extension CatalogRepository {
    func channel(number: Int, for profileID: UUID) async throws -> Channel? { nil }
    func firstChannel(for profileID: UUID) async throws -> Channel? { nil }
    func setNumber(_ number: Int, forChannelID id: String, for profileID: UUID) async throws {}
    func renumberByGroups(_ groupOrder: [String], for profileID: UUID) async throws {}
}

/// Lokaler Programmführer (wird nicht über iCloud synchronisiert). `channelIDs` sind EPG-IDs.
public protocol EPGRepository: Sendable {
    /// Ersetzt das EPG des Profils erst nach vollständigem Lesen des Stroms.
    func importProgrammes(for profileID: UUID, from programmes: AsyncThrowingStream<EPGProgramme, Error>) async throws
    func programmes(for profileID: UUID, channelIDs: [String], from: Date, to: Date) async throws -> [EPGProgramme]
    func nowNext(for profileID: UUID, channelIDs: [String], at date: Date) async throws -> [String: NowNext]
    func lastUpdate(for profileID: UUID) async throws -> Date?
    func deleteEPG(for profileID: UUID) async throws
    /// Sendungen mit `query` im Titel, die im Zeitraum laufen oder beginnen, nach Beginn sortiert.
    func searchProgrammes(for profileID: UUID, query: String, from: Date, to: Date, limit: Int) async throws -> [EPGProgramme]
}

public protocol EPGProviding: Sendable {
    /// Liefert nur Sendungen der erlaubten Sender, die das Zeitfenster berühren.
    func programmes(
        allowedChannelIDs: Set<String>, window: DateInterval
    ) async throws -> AsyncThrowingStream<EPGProgramme, Error>
}

public protocol ProfileRepository: Sendable {
    func profiles() async throws -> [Profile]
    func save(_ profile: Profile) async throws
    func delete(id: UUID) async throws
    /// Zuletzt gesehener Sender (und ggf. Timeshift-Stelle), über iCloud auf allen Geräten gleich.
    func liveResumeState(for profileID: UUID) async throws -> LiveResumeState?
    func setLiveResumeState(_ state: LiveResumeState?, for profileID: UUID) async throws
}

public protocol LiveChannelProviding: Sendable {
    func liveChannels() async throws -> [Channel]
}

/// Sender als Strom, damit auch sehr grosse Playlists nicht komplett im Speicher liegen müssen.
public protocol LiveCatalogStreaming: Sendable {
    func channelStream() async throws -> AsyncThrowingStream<Channel, Error>
}

/// Lokaler Film- und Serienkatalog (wird nicht über iCloud synchronisiert).
public protocol VODRepository: Sendable {
    /// Ersetzt die Liste dieser Art erst nach vollständigem Lesen des Stroms.
    func importItems(for profileID: UUID, kind: VODKind, from items: AsyncThrowingStream<VODItem, Error>) async throws
    func groups(for profileID: UUID, kind: VODKind) async throws -> [ChannelGroup]
    func items(for profileID: UUID, kind: VODKind, group: String, limit: Int) async throws -> [VODItem]
    func deleteVOD(for profileID: UUID) async throws
    func searchItems(for profileID: UUID, kind: VODKind, query: String, limit: Int) async throws -> [VODItem]
    func lastUpdate(for profileID: UUID, kind: VODKind) async throws -> Date?
    func item(for profileID: UUID, kind: VODKind, sourceID: Int) async throws -> VODItem?
    /// Die zuletzt vom Anbieter hinzugefügten Einträge (neueste zuerst); Einträge ohne Datum fehlen.
    func recentItems(for profileID: UUID, kind: VODKind, limit: Int) async throws -> [VODItem]
}

/// Merkt sich pro Gerät, welches Profil zuletzt aktiv war (bewusst nicht synchronisiert).
public protocol ActiveProfileStore: Sendable {
    var activeProfileID: UUID? { get }
    func setActiveProfileID(_ id: UUID?)
}

public protocol VODProviding: Sendable {
    func vodItems(kind: VODKind) async throws -> [VODItem]
    func movieDetail(for item: VODItem) async throws -> MovieDetail
    func seriesDetail(for item: VODItem) async throws -> SeriesDetail
}

/// Wiedergabestand pro Profil (Nutzerdaten, per CloudKit synchronisiert).
///
/// Konfliktregel: Jedes Gerät schreibt seinen eigenen Eintrag pro Inhalt; gelesen wird der Eintrag mit der neuesten
/// Ereigniszeit. Die Ereigniszeit liegt immer nach allen bereits bekannten Einträgen (hybride Uhr), daher gewinnt die
/// zuletzt bewusst ausgeführte Aktion auch bei abweichenden Geräteuhren, und ein verspätet hochgeladener älterer
/// Stand überschreibt nichts. `deleteProgress` setzt eine Löschmarke, hinter die ältere Einträge nicht zurückkommen.
public protocol ProgressRepository: Sendable {
    func progress(for profileID: UUID, ids: [String]) async throws -> [String: WatchProgress]
    func allProgress(for profileID: UUID) async throws -> [WatchProgress]
    func save(_ progress: WatchProgress, for profileID: UUID) async throws
    /// Angefangene, nicht gesehene Einträge, neueste zuerst; pro Serie nur die zuletzt gesehene Episode.
    func continueWatching(for profileID: UUID, limit: Int) async throws -> [WatchProgress]
    func setWatched(_ watched: Bool, target: PlaybackTarget, for profileID: UUID) async throws
    func deleteProgress(for profileID: UUID) async throws
}

/// Zustand des iCloud-Abgleichs, so wie ihn die Oberfläche zeigt.
public enum SyncStatus: Sendable, Equatable {
    /// Diese Version enthält keinen iCloud-Abgleich (Kompilierflag `ICLOUD_SYNC` fehlt).
    case unavailable
    /// In den Einstellungen der App ausgeschaltet.
    case disabled
    case checking
    case noAccount
    /// Durch Bildschirmzeit/MDM gesperrt.
    case restricted
    /// Konto vorübergehend nicht nutzbar (z. B. nicht bestätigte Anmeldung).
    case temporarilyUnavailable
    case syncing
    case upToDate(lastSync: Date?)
    case failed(SyncProblem)
}

public enum SyncProblem: Sendable, Equatable {
    case network
    case quotaExceeded
    case rateLimited
    case accountChanged
    case other(String)
}

/// Meldet den Zustand des Abgleichs und dass andere Geräte Daten geändert haben.
@MainActor
public protocol SyncMonitoring: AnyObject {
    var status: SyncStatus { get }
    /// Liefert einen Wert, sobald Änderungen anderer Geräte importiert wurden.
    func remoteChanges() -> AsyncStream<Void>
    /// Fragt den Kontostatus neu ab (App-Start, Rückkehr in den Vordergrund).
    func refresh() async
}
