#if os(iOS)
import ARJOCore
import ARJOPlayer
@preconcurrency import CarPlay
import MediaPlayer
import OSLog
import UIKit

/// Bindet die laufende Sitzung an CarPlay: Listen (Favoriten, Zuletzt, Kategorien) und «Läuft gerade».
/// Benötigt die von Apple freizugebenden Berechtigungen `com.apple.developer.carplay-audio` bzw. `com.apple.developer.carplay-video`
/// (siehe `docs/CarPlay.md`). Ohne sie verbindet sich CarPlay nie mit der App, und der Code bleibt ohne Wirkung.
@MainActor
public final class CarPlayCoordinator: NSObject, CPSessionConfigurationDelegate {
    public static let shared = CarPlayCoordinator()

    public private(set) var state: CarPlayVideoState = .disconnected
    private weak var session: ProfileSession?
    private var interfaceController: CPInterfaceController?
    private var configuration: CPSessionConfiguration?
    private let log = Logger(subsystem: "ch.arjo.iptelevision", category: "carplay")
    private var limitedUserInterfaces: CPLimitableUserInterface = []
    /// Zeilen pro Liste: Wert des Systems (kleiner bei eingeschränkten Listen), höchstens `preferredMaxItems`.
    private var itemLimit: Int { CarPlayDrivingLimits.itemLimit(systemMaximum: Int(CPListTemplate.maximumItemCount)) }

    private override init() { super.init() }

    /// Die aktive Sitzung; wird beim Start jeder Sitzung gesetzt.
    func attach(session: ProfileSession) {
        self.session = session
        NowPlayingPublisher.shared.attach(live: session.live)
        if interfaceController != nil { Task { await rebuild() } }
    }

    public func connect(_ controller: CPInterfaceController) {
        interfaceController = controller
        let configuration = CPSessionConfiguration(delegate: self)
        self.configuration = configuration
        refreshState()
        Task { await rebuild() }
    }

    public func disconnect() {
        interfaceController = nil
        configuration = nil
        state = .disconnected
        // Die Wiedergabe läuft auf dem iPhone weiter und ist dort bedienbar.
    }

    private func refreshState() {
        var supportsVideo = false
        if #available(iOS 26.4, *) { supportsVideo = configuration?.supportsVideoPlayback ?? false }
        limitedUserInterfaces = configuration?.limitedUserInterfaces ?? []
        state = CarPlayVideoState.resolve(isConnected: interfaceController != nil, supportsVideo: supportsVideo)
        log.info("CarPlay-Zustand: \(String(describing: self.state))")
    }

    // MARK: Oberfläche

    private func rebuild() async {
        guard let controller = interfaceController, let session else { return }
        let favorites = listTemplate(title: String(localized: "Favoriten"), symbol: "star.fill", channels: session.organization.favorites, session: session)
        let recent = listTemplate(title: String(localized: "Zuletzt"), symbol: "clock", channels: session.live.lastChannel.map { [$0] } ?? [], session: session)
        let categories = categoriesTemplate(session: session)
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.tabTitle = String(localized: "Läuft")
        nowPlaying.tabImage = UIImage(systemName: "play.tv")
        let tabs = CPTabBarTemplate(templates: [favorites, recent, categories, nowPlaying])
        do { try await controller.setRootTemplate(tabs, animated: false) } catch { log.error("Root-Template: \(error.localizedDescription)") }
    }

    private func listTemplate(title: String, symbol: String, channels: [Channel], session: ProfileSession) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [section(for: channels, session: session)])
        template.tabImage = UIImage(systemName: symbol)
        template.emptyViewTitleVariants = [String(localized: "Nichts hier. Starte einen Sender auf dem iPhone.")]
        return template
    }

    private func categoriesTemplate(session: ProfileSession) -> CPListTemplate {
        let items = session.live.groups.prefix(itemLimit).map { group -> CPListItem in
            let item = CPListItem(text: CarPlayDrivingLimits.glanceable(session.organization.name(forGroup: group.name, in: .live)), detailText: "\(group.channelCount)")
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.showGroup(group)
                    completion()
                }
            }
            return item
        }
        let template = CPListTemplate(title: String(localized: "Kategorien"), sections: [CPListSection(items: Array(items))])
        template.tabImage = UIImage(systemName: "square.grid.2x2")
        return template
    }

    private func showGroup(_ group: ChannelGroup) async {
        guard let session, let controller = interfaceController else { return }
        do {
            let channels = try await session.live.channels(in: group)
            let template = CPListTemplate(title: CarPlayDrivingLimits.glanceable(session.organization.name(forGroup: group.name, in: .live)), sections: [section(for: channels, session: session)])
            try await controller.pushTemplate(template, animated: true)
        } catch {
            log.error("Gruppe \(group.name): \(error.localizedDescription)")
        }
    }

    private func section(for channels: [Channel], session: ProfileSession) -> CPListSection {
        let visible = channels.filter { !session.organization.isHidden($0) && !session.parental.isLocked(.live, $0.groupName) }
        let rows = CarPlayRows.make(
            from: visible, limit: itemLimit,
            name: { session.organization.name(for: $0) },
            nowTitle: { session.live.epg.nowNext(for: $0)?.now?.title }
        )
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = rows.compactMap { row -> CPListItem? in
            guard let channel = byID[row.id] else { return nil }
            let item = CPListItem(text: row.title, detailText: row.subtitle)
            if #available(iOS 26.4, *) {
                // Live: Dauer unbekannt (0). Video nur anbieten, wenn die Sitzung es unterstützt; sonst «Läuft gerade».
                item.playbackConfiguration = CPPlaybackConfiguration(
                    preferredPresentation: state.presentsVideo ? .video : .audio,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
            }
            if let url = row.logoURL { loadLogo(url, into: item) }
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.play(channel, in: visible)
                    completion()
                }
            }
            return item
        }
        return CPListSection(items: items)
    }

    private func loadLogo(_ url: URL, into item: CPListItem) {
        Task { @MainActor in
            guard let cgImage = await ImageLoader.shared.image(for: url, maxPixel: Int(max(CPListItem.maximumImageSize.width, CPListItem.maximumImageSize.height) * UIScreen.main.scale)) else { return }
            item.setImage(UIImage(cgImage: cgImage))
        }
    }

    private func play(_ channel: Channel, in queue: [Channel]) {
        guard let session, let controller = interfaceController else { return }
        // Bestehende Wiedergabe-Pipeline; das Fenster auf dem iPhone bleibt, wie es ist.
        session.live.play(channel, in: queue, presenting: false)
        if !controller.templates.contains(where: { $0 === CPNowPlayingTemplate.shared }) || state.presentsVideo == false {
            controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { _, _ in }
        }
    }

    // MARK: CPSessionConfigurationDelegate

    public func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration, limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        refreshState()
        // Listen kürzer, sobald das Fahrzeug sie einschränkt (Fahrt); beim Wechsel zurück wieder vollständig.
        Task { await rebuild() }
    }
}
#endif
