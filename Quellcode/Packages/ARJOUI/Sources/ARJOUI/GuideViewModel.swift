import ARJOCore
import Foundation
import Observation

/// Zustand des Programmführer-Rasters: eine Gruppe, ein Zeitfenster von drei Stunden.
@MainActor
@Observable
public final class GuideViewModel {
    public static let windowLength: TimeInterval = 3 * 3_600
    private static let slot: TimeInterval = 30 * 60

    public private(set) var selectedGroup: ChannelGroup?
    public private(set) var channels: [Channel] = []
    public private(set) var programmes: [String: [EPGProgramme]] = [:]
    public private(set) var windowStart: Date
    public private(set) var errorMessage: String?

    private let live: LiveTVViewModel
    private let clock: () -> Date
    private let isAllowed: @MainActor (ChannelGroup) -> Bool
    private let isVisible: @MainActor (Channel) -> Bool

    /// - Parameter isAllowed: Blendet Gruppen aus, die die Kindersicherung gerade sperrt.
    public init(
        live: LiveTVViewModel,
        clock: @escaping () -> Date = { Date() },
        isAllowed: @escaping @MainActor (ChannelGroup) -> Bool = { _ in true },
        isVisible: @escaping @MainActor (Channel) -> Bool = { _ in true }
    ) {
        self.isVisible = isVisible
        self.live = live
        self.clock = clock
        self.isAllowed = isAllowed
        windowStart = Self.initialWindowStart(for: clock())
    }

    public var windowEnd: Date { windowStart.addingTimeInterval(Self.windowLength) }

    public func programmes(for channel: Channel) -> [EPGProgramme] {
        channel.epgChannelID.flatMap { programmes[$0] } ?? []
    }

    public var allowedGroups: [ChannelGroup] { live.groups.filter(isAllowed) }

    public func load() async {
        if selectedGroup.map(isAllowed) != true { selectedGroup = allowedGroups.first }
        guard let group = selectedGroup else {
            channels = []
            programmes = [:]
            return
        }
        await loadChannels(of: group)
    }

    public func select(_ group: ChannelGroup) async {
        selectedGroup = group
        await loadChannels(of: group)
    }

    public func shiftWindow(hours: Int) async {
        windowStart = windowStart.addingTimeInterval(Double(hours) * 3_600)
        await reloadProgrammes()
    }

    public func jumpToNow() async {
        windowStart = Self.initialWindowStart(for: clock())
        await reloadProgrammes()
    }

    public func reloadProgrammes() async {
        do {
            programmes = try await live.epg.programmes(for: channels, from: windowStart, to: windowEnd)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Der Programmführer konnte nicht gelesen werden.")
        }
    }

    private func loadChannels(of group: ChannelGroup) async {
        do {
            channels = try await live.channels(in: group).filter(isVisible)
        } catch {
            channels = []
            errorMessage = String(localized: "Die Sender dieser Gruppe konnten nicht geladen werden.")
            return
        }
        await reloadProgrammes()
    }

    /// Beginnt eine halbe Stunde vor der letzten vollen halben Stunde, damit «Jetzt» nicht am Rand klebt.
    private static func initialWindowStart(for date: Date) -> Date {
        let rounded = (date.timeIntervalSince1970 / slot).rounded(.down) * slot
        return Date(timeIntervalSince1970: rounded - slot)
    }
}
