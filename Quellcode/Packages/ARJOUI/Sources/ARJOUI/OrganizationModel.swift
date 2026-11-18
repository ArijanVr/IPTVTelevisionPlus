import ARJOCore
import Foundation
import Observation
import OSLog

/// Favoriten, eigene Ordner, ausgeblendete und umbenannte Sender und Gruppen eines Profils.
@MainActor
@Observable
public final class OrganizationModel {
    /// Eine offene Eingabe (Umbenennen, neuer Ordner), die ein zentrales Fenster anzeigt.
    public enum PendingEdit: Identifiable, Equatable {
        case renameChannel(Channel)
        case renameGroup(GroupArea, String)
        case newFolder(adding: Channel?)
        case renameFolder(ChannelFolder)

        public var id: String {
            switch self {
            case .renameChannel(let channel): "channel-\(channel.id)"
            case .renameGroup(let area, let name): "group-\(area.rawValue)-\(name)"
            case .newFolder(let channel): "folder-new-\(channel?.id ?? "")"
            case .renameFolder(let folder): "folder-\(folder.id)"
            }
        }
    }

    private static let log = Logger(subsystem: "ch.arjo.iptelevision", category: "organization")

    public private(set) var preferences: [String: Preference] = [:]
    public private(set) var folders: [ChannelFolder] = []
    /// Favoriten in eigener Reihenfolge, aufgelöst aus dem Katalog.
    public private(set) var favorites: [Channel] = []
    public private(set) var folderChannels: [UUID: [Channel]] = [:]
    public private(set) var hiddenChannels: [Channel] = []
    /// Zählt jede Änderung hoch, damit Ansichten neu laden.
    public private(set) var revision = 0
    public var pendingEdit: PendingEdit?
    public private(set) var errorMessage: String?

    private let profile: Profile
    private let repository: any OrganizationRepository
    private let catalog: any CatalogRepository

    public init(profile: Profile, repository: any OrganizationRepository, catalog: any CatalogRepository) {
        self.profile = profile
        self.repository = repository
        self.catalog = catalog
    }

    // MARK: Lesen

    public func name(for channel: Channel) -> String {
        preferences[PreferenceKey.channel(channel.id)]?.customName ?? channel.name
    }

    public func name(forGroup name: String, in area: GroupArea) -> String {
        preferences[PreferenceKey.group(area, name)]?.customName ?? name
    }

    public func isFavorite(_ channel: Channel) -> Bool {
        preferences[PreferenceKey.channel(channel.id)]?.isFavorite ?? false
    }

    public func isHidden(_ channel: Channel) -> Bool {
        preferences[PreferenceKey.channel(channel.id)]?.isHidden ?? false
    }

    public func isHidden(group name: String, in area: GroupArea) -> Bool {
        preferences[PreferenceKey.group(area, name)]?.isHidden ?? false
    }

    public func visible(_ channels: [Channel]) -> [Channel] {
        channels.filter { !isHidden($0) }
    }

    /// Ohne ausgeblendete Gruppen, in der eigenen Reihenfolge (Gruppen ohne eigene Position folgen in der Reihenfolge des Anbieters).
    public func visible(_ groups: [ChannelGroup], in area: GroupArea) -> [ChannelGroup] {
        ordered(groups, in: area).filter { !isHidden(group: $0.name, in: area) }
    }

    /// Alle Gruppen in der eigenen Reihenfolge, auch ausgeblendete.
    public func ordered(_ groups: [ChannelGroup], in area: GroupArea) -> [ChannelGroup] {
        let indexed = groups.enumerated().map { offset, group in
            (group, preferences[PreferenceKey.group(area, group.name)]?.sortIndex ?? Int.max, offset)
        }
        return indexed.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
    }

    public func hasCustomOrder(in area: GroupArea, groups: [ChannelGroup]) -> Bool {
        groups.contains { preferences[PreferenceKey.group(area, $0.name)]?.sortIndex != nil }
    }

    private var hiddenChannelIDs: [String] { ids(withPrefix: "channel:") { $0.isHidden } }
    public var hiddenGroupKeys: [String] { ids(withPrefix: "group:") { $0.isHidden } }

    // MARK: Laden

    public func load() async {
        do {
            async let loadedPreferences = repository.preferences(for: profile.id)
            async let loadedFolders = repository.folders(for: profile.id)
            (preferences, folders) = try await (loadedPreferences, loadedFolders)
        } catch {
            fail(String(localized: "Favoriten und Ordner konnten nicht gelesen werden."), error)
            return
        }
        await resolveChannels()
    }

    // MARK: Favoriten

    public func toggleFavorite(_ channel: Channel) async {
        var preference = current(for: channel)
        preference.isFavorite.toggle()
        preference.favoriteOrder = preference.isFavorite ? favorites.count : 0
        await save(preference)
    }

    /// Verschiebt einen Favoriten um `offset` Plätze (negativ = nach oben).
    public func moveFavorite(_ channel: Channel, by offset: Int) async {
        var ids = favorites.map(\.id)
        guard let index = ids.firstIndex(of: channel.id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        await perform(String(localized: "Die Reihenfolge konnte nicht gespeichert werden.")) {
            try await repository.setFavoriteOrder(ids, for: profile.id)
        }
        await load()
    }

    // MARK: Ausblenden und Umbenennen

    public func setHidden(_ hidden: Bool, _ channel: Channel) async {
        var preference = current(for: channel)
        preference.isHidden = hidden
        await save(preference)
    }

    public func setHidden(_ hidden: Bool, group name: String, in area: GroupArea) async {
        var preference = preferences[PreferenceKey.group(area, name)] ?? Preference(key: PreferenceKey.group(area, name))
        preference.isHidden = hidden
        await save(preference)
    }

    public func rename(_ channel: Channel, to name: String?) async {
        var preference = current(for: channel)
        preference.customName = Self.normalized(name)
        await save(preference)
    }

    public func renameGroup(_ group: String, in area: GroupArea, to name: String?) async {
        var preference = preferences[PreferenceKey.group(area, group)] ?? Preference(key: PreferenceKey.group(area, group))
        preference.customName = Self.normalized(name)
        await save(preference)
    }

    /// Verschiebt eine Gruppe um `offset` Plätze (negativ = nach oben).
    public func moveGroup(_ name: String, in area: GroupArea, among groups: [ChannelGroup], by offset: Int) async {
        var names = ordered(groups, in: area).map(\.name)
        guard let index = names.firstIndex(of: name), names.indices.contains(index + offset) else { return }
        names.insert(names.remove(at: index), at: index + offset)
        await assignOrder(names, in: area)
    }

    /// Verschiebt Gruppen per Ziehen (Indizes beziehen sich auf `ordered(groups, in:)`, auch ausgeblendete).
    public func moveGroups(in area: GroupArea, among groups: [ChannelGroup], fromOffsets source: IndexSet, toOffset destination: Int) async {
        var names = ordered(groups, in: area).map(\.name)
        names.move(fromOffsets: source, toOffset: destination)
        await assignOrder(names, in: area)
    }

    /// Verschiebt Favoriten per Ziehen.
    public func moveFavorites(fromOffsets source: IndexSet, toOffset destination: Int) async {
        var ids = favorites.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        await perform(String(localized: "Die Reihenfolge konnte nicht gespeichert werden.")) {
            try await repository.setFavoriteOrder(ids, for: profile.id)
        }
        await load()
    }

    /// Sender in der eigenen Reihenfolge (Sender ohne eigene Position folgen in der Reihenfolge des Anbieters).
    public func ordered(_ channels: [Channel]) -> [Channel] {
        let indexed = channels.enumerated().map { offset, channel in
            (channel, preferences[PreferenceKey.channel(channel.id)]?.sortIndex ?? Int.max, offset)
        }
        return indexed.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
    }

    /// Verschiebt einen Sender per Ziehen an die Stelle eines anderen derselben Liste (Gruppe oder Kategorie).
    public func moveChannel(_ id: String, to targetID: String, among channels: [Channel]) async {
        var ids = ordered(channels).map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: targetID), from != to else { return }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
        await assignChannelOrder(ids)
    }

    /// Verschiebt Sender einer Liste (z. B. im Listen-Editor per Ziehen).
    public func moveChannels(among channels: [Channel], fromOffsets source: IndexSet, toOffset destination: Int) async {
        var ids = ordered(channels).map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        await assignChannelOrder(ids)
    }

    /// Verschiebt einen Favoriten per Ziehen an die Stelle eines anderen.
    public func moveFavorite(_ id: String, to targetID: String) async {
        let ids = favorites.map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: targetID), from != to else { return }
        await moveFavorites(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
    }

    /// Verschiebt einen Sender per Ziehen innerhalb eines Ordners an die Stelle eines anderen.
    public func move(_ id: String, to targetID: String, in folder: ChannelFolder) async {
        var updated = folder
        guard let from = updated.channelIDs.firstIndex(of: id), let to = updated.channelIDs.firstIndex(of: targetID), from != to else { return }
        updated.channelIDs.move(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
        await save(updated)
    }

    private func assignChannelOrder(_ ids: [String]) async {
        for (index, id) in ids.enumerated() {
            let key = PreferenceKey.channel(id)
            var preference = preferences[key] ?? Preference(key: key)
            guard preference.sortIndex != index else { continue }
            preference.sortIndex = index
            await save(preference, resolve: false)
        }
        revision += 1
    }

    /// Stellt die Reihenfolge des Anbieters wieder her.
    public func resetGroupOrder(in area: GroupArea, among groups: [ChannelGroup]) async {
        for group in groups {
            let key = PreferenceKey.group(area, group.name)
            guard var preference = preferences[key], preference.sortIndex != nil else { continue }
            preference.sortIndex = nil
            await save(preference, resolve: false)
        }
        revision += 1
    }

    private func assignOrder(_ names: [String], in area: GroupArea) async {
        for (index, name) in names.enumerated() {
            let key = PreferenceKey.group(area, name)
            var preference = preferences[key] ?? Preference(key: key)
            guard preference.sortIndex != index else { continue }
            preference.sortIndex = index
            await save(preference, resolve: false)
        }
        revision += 1
    }

    /// Schlüssel einer ausgeblendeten Gruppe wieder einblenden (Einstellungen).
    public func unhide(key: String) async {
        guard var preference = preferences[key] else { return }
        preference.isHidden = false
        await save(preference)
    }

    // MARK: Ordner

    public func createFolder(named name: String, adding channel: Channel? = nil) async {
        guard let name = Self.normalized(name) else { return }
        await save(ChannelFolder(name: name, channelIDs: channel.map { [$0.id] } ?? []))
    }

    public func renameFolder(_ folder: ChannelFolder, to name: String) async {
        guard let name = Self.normalized(name) else { return }
        var updated = folder
        updated.name = name
        await save(updated)
    }

    public func deleteFolder(_ folder: ChannelFolder) async {
        await perform(String(localized: "Der Ordner konnte nicht gelöscht werden.")) {
            try await repository.deleteFolder(id: folder.id, for: profile.id)
        }
        await load()
    }

    public func add(_ channel: Channel, to folder: ChannelFolder) async {
        guard !folder.channelIDs.contains(channel.id) else { return }
        var updated = folder
        updated.channelIDs.append(channel.id)
        await save(updated)
    }

    public func remove(_ channel: Channel, from folder: ChannelFolder) async {
        var updated = folder
        updated.channelIDs.removeAll { $0 == channel.id }
        await save(updated)
    }

    public func move(_ channel: Channel, in folder: ChannelFolder, by offset: Int) async {
        var updated = folder
        guard let index = updated.channelIDs.firstIndex(of: channel.id),
              updated.channelIDs.indices.contains(index + offset) else { return }
        updated.channelIDs.swapAt(index, index + offset)
        await save(updated)
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: Intern

    private func current(for channel: Channel) -> Preference {
        preferences[PreferenceKey.channel(channel.id)] ?? Preference(key: PreferenceKey.channel(channel.id))
    }

    private func ids(withPrefix prefix: String, where predicate: (Preference) -> Bool) -> [String] {
        preferences.values.filter { $0.key.hasPrefix(prefix) && predicate($0) }.map(\.key).sorted()
    }

    private func save(_ preference: Preference, resolve: Bool = true) async {
        let saved = await perform(String(localized: "Die Änderung konnte nicht gespeichert werden.")) {
            try await repository.save(preference, for: profile.id)
        }
        guard saved else { return }
        preferences[preference.key] = preference.isDefault ? nil : preference
        if resolve { await resolveChannels() }
    }

    private func save(_ folder: ChannelFolder) async {
        let saved = await perform(String(localized: "Der Ordner konnte nicht gespeichert werden.")) {
            try await repository.save(folder, for: profile.id)
        }
        guard saved else { return }
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
        } else {
            folders.append(folder)
        }
        await resolveChannels()
    }

    private func resolveChannels() async {
        let favoriteIDs = preferences.values
            .filter { $0.key.hasPrefix("channel:") && $0.isFavorite }
            .sorted { ($0.favoriteOrder, $0.key) < ($1.favoriteOrder, $1.key) }
            .map { String($0.key.dropFirst("channel:".count)) }
        favorites = await channels(for: favoriteIDs)
        hiddenChannels = await channels(for: hiddenChannelIDs.map { String($0.dropFirst("channel:".count)) })

        var resolved: [UUID: [Channel]] = [:]
        for folder in folders { resolved[folder.id] = await channels(for: folder.channelIDs) }
        folderChannels = resolved
        revision += 1
    }

    private func channels(for ids: [String]) async -> [Channel] {
        var result: [Channel] = []
        for id in ids {
            do {
                if let channel = try await catalog.channel(id: id, for: profile.id) { result.append(channel) }
            } catch {
                Self.log.error("Sender nicht gelesen: \(error.localizedDescription)")
            }
        }
        return result
    }

    @discardableResult
    private func perform(_ failure: String, _ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            return true
        } catch {
            fail(failure, error)
            return false
        }
    }

    private func fail(_ message: String, _ error: Error) {
        Self.log.error("\(message) \(error.localizedDescription)")
        errorMessage = message
    }

    private static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
