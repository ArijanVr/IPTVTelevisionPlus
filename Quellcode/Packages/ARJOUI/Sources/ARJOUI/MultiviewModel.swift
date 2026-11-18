import ARJOCore
import ARJONetwork
import ARJOPlayer
import Foundation
import Observation

/// Anordnung der Bilder im Multiview.
public enum MultiviewLayout: String, CaseIterable, Identifiable, Sendable {
    /// Gleich grosse Bilder im Raster.
    case grid
    /// Das Bild mit Ton gross, die anderen klein daneben (bzw. darunter im Hochformat).
    case focus
    /// Das Bild mit Ton gross oben, die anderen klein in einer Reihe darunter.
    case stage
    /// Alle Bilder in einer Reihe (im Hochformat untereinander).
    case strip
    /// Das Bild mit Ton füllt alles, die anderen schweben klein in der Ecke unten rechts.
    case pip

    public var id: Self { self }

    public var title: String {
        switch self {
        case .grid: String(localized: "Raster")
        case .focus: String(localized: "Fokus")
        case .stage: String(localized: "Bühne")
        case .strip: String(localized: "Reihe")
        case .pip: String(localized: "Bild in Bild")
        }
    }

    public var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .focus: "rectangle.leadinghalf.inset.filled"
        case .stage: "rectangle.tophalf.inset.filled"
        case .strip: "rectangle.split.3x1"
        case .pip: "pip"
        }
    }

    /// Bei «Bild in Bild» liegen die kleinen Bilder über dem grossen; sonst teilen sich die Bilder die Fläche.
    var overlaps: Bool { self == .pip }

    /// Positionen für `count` Bilder in `size`; `focus` ist das grosse Bild (Fokus, Bühne, Bild in Bild).
    /// Es gibt nur so viele Felder wie laufende Bilder: Ausser bei «Bild in Bild» füllen sie die Fläche ganz, ohne leere Plätze.
    func frames(count: Int, in size: CGSize, focus: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let landscape = size.width >= size.height
        func equal(columns: Int, rows: Int, order: [Int]? = nil) -> [CGRect] {
            let tile = CGSize(width: size.width / CGFloat(columns), height: size.height / CGFloat(rows))
            return (0..<count).map { index in
                CGRect(x: CGFloat(index % columns) * tile.width, y: CGFloat(index / columns) * tile.height,
                       width: tile.width, height: tile.height)
            }
        }
        switch self {
        case .grid:
            // Zeilen mit je eigener Spaltenzahl: 3 Bilder = 2 oben, 1 unten über die ganze Breite.
            let rows: [Int] = switch count {
            case 1: [1]
            case 2: landscape ? [2] : [1, 1]
            case 3: [2, 1]
            default: [2, 2]
            }
            let rowHeight = size.height / CGFloat(rows.count)
            return rows.enumerated().flatMap { row, columns in
                (0..<columns).map { column in
                    CGRect(x: size.width / CGFloat(columns) * CGFloat(column), y: rowHeight * CGFloat(row),
                           width: size.width / CGFloat(columns), height: rowHeight)
                }
            }
        case .pip:
            let big = min(max(focus, 0), count - 1)
            let margin = min(size.width, size.height) * 0.04
            let smallWidth = size.width * (landscape ? 0.22 : 0.4)
            let smallHeight = smallWidth * 9 / 16
            var smallIndex: CGFloat = 0
            return (0..<count).map { index in
                if index == big { return CGRect(origin: .zero, size: size) }
                defer { smallIndex += 1 }
                return CGRect(x: size.width - margin - smallWidth,
                              y: size.height - margin - smallHeight - (smallHeight + margin / 2) * smallIndex,
                              width: smallWidth, height: smallHeight)
            }
        case .strip:
            return landscape ? equal(columns: count, rows: 1) : equal(columns: 1, rows: count)
        case .stage:
            guard count > 1 else { return [CGRect(origin: .zero, size: size)] }
            let big = min(max(focus, 0), count - 1)
            let bigHeight = size.height * (landscape ? 0.74 : 0.55)
            let small = CGFloat(count - 1)
            var smallIndex: CGFloat = 0
            return (0..<count).map { index in
                if index == big { return CGRect(x: 0, y: 0, width: size.width, height: bigHeight) }
                defer { smallIndex += 1 }
                return CGRect(x: size.width / small * smallIndex, y: bigHeight,
                              width: size.width / small, height: size.height - bigHeight)
            }
        case .focus:
            guard count > 1 else { return [CGRect(origin: .zero, size: size)] }
            let big = min(max(focus, 0), count - 1)
            let small = count - 1
            let bigRect = landscape
                ? CGRect(x: 0, y: 0, width: size.width * 0.7, height: size.height)
                : CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.62)
            let rest = landscape
                ? CGRect(x: bigRect.maxX, y: 0, width: size.width - bigRect.maxX, height: size.height)
                : CGRect(x: 0, y: bigRect.maxY, width: size.width, height: size.height - bigRect.maxY)
            var smallIndex = 0
            return (0..<count).map { index in
                if index == big { return bigRect }
                defer { smallIndex += 1 }
                return landscape
                    ? CGRect(x: rest.minX, y: rest.minY + rest.height / CGFloat(small) * CGFloat(smallIndex),
                             width: rest.width, height: rest.height / CGFloat(small))
                    : CGRect(x: rest.minX + rest.width / CGFloat(small) * CGFloat(smallIndex), y: rest.minY,
                             width: rest.width / CGFloat(small), height: rest.height)
            }
        }
    }
}

/// Bis zu vier Sender gleichzeitig. Nur ein Bild hat Ton, die anderen laufen stumm und mit begrenzter Bitrate.
@MainActor
@Observable
public final class MultiviewModel {
    public struct Slot: Identifiable {
        public let id = UUID()
        public var channel: Channel
        public let engine: HybridPlaybackEngine
        public let playback: PlaybackController
    }

    public static let maxSlots = 4
    /// Bitrate der stummen Bilder, sobald mehrere laufen.
    static let backgroundBitRate: Double = 2_500_000

    public private(set) var slots: [Slot] = []
    public private(set) var audioSlotID: UUID?
    public private(set) var message: String?
    public var isPresented = false
    /// Wird für die nächste Sitzung gemerkt.
    public var layout: MultiviewLayout = MultiviewLayout(rawValue: UserDefaults.standard.string(forKey: "multiview.layout") ?? "") ?? .grid {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: "multiview.layout") }
    }
    /// Gesetzt, wenn die Senderwahl einen bestimmten Platz ersetzen soll; `nil` = neuen Platz belegen.
    public var replacingSlotID: UUID?
    public var isPickingChannel = false
    /// Wird vor dem Anzeigen aufgerufen (z. B. das normale Live-Bild beenden).
    @ObservationIgnored public var onWillPresent: (() -> Void)?

    private let profile: Profile
    private let credentialStore: any CredentialStore
    private let makeEngine: @MainActor () -> HybridPlaybackEngine

    public init(profile: Profile, credentialStore: any CredentialStore, makeEngine: @escaping @MainActor () -> HybridPlaybackEngine) {
        self.profile = profile
        self.credentialStore = credentialStore
        self.makeEngine = makeEngine
    }

    public var canAddSlot: Bool { slots.count < Self.maxSlots }

    /// Öffnet das Multiview und nimmt `channel` dazu (falls angegeben).
    public func present(adding channel: Channel? = nil) {
        onWillPresent?()
        isPresented = true
        if let channel { add(channel) }
    }

    @discardableResult
    public func add(_ channel: Channel) -> Bool {
        guard canAddSlot else {
            message = String(localized: "Es sind höchstens \(Self.maxSlots) Bilder gleichzeitig möglich.")
            return false
        }
        guard !slots.contains(where: { $0.channel.id == channel.id }) else {
            message = String(localized: "Dieser Sender läuft schon im Multiview.")
            return false
        }
        message = nil
        let engine = makeEngine()
        let slot = Slot(channel: channel, engine: engine, playback: PlaybackController(engine: engine))
        slots.append(slot)
        if audioSlotID == nil { audioSlotID = slot.id }
        applyAudioAndQuality()
        start(slot)
        return true
    }

    /// Ersetzt den Sender eines Platzes.
    public func replace(slotID: UUID, with channel: Channel) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        guard !slots.contains(where: { $0.channel.id == channel.id && $0.id != slotID }) else {
            message = String(localized: "Dieser Sender läuft schon im Multiview.")
            return
        }
        message = nil
        slots[index].channel = channel
        start(slots[index])
    }

    public func remove(slotID: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        slots[index].playback.stop()
        slots.remove(at: index)
        if audioSlotID == slotID { audioSlotID = slots.first?.id }
        applyAudioAndQuality()
    }

    public func setAudio(slotID: UUID) {
        guard slots.contains(where: { $0.id == slotID }) else { return }
        audioSlotID = slotID
        applyAudioAndQuality()
    }

    /// Beendet alle Bilder und leert das Multiview.
    public func closeAll() {
        slots.forEach { $0.playback.stop() }
        slots = []
        audioSlotID = nil
        message = nil
        isPresented = false
        isPickingChannel = false
        replacingSlotID = nil
    }

    public func dismissMessage() {
        message = nil
    }

    private func applyAudioAndQuality() {
        for slot in slots {
            let hasAudio = slot.id == audioSlotID
            slot.engine.isMuted = !hasAudio
            slot.engine.maxBitRate = hasAudio || slots.count == 1 ? 0 : Self.backgroundBitRate
        }
    }

    private func start(_ slot: Slot) {
        let channel = slot.channel
        slot.playback.play { [credentialStore, profile] in
            guard let credentials = try credentialStore.load(for: profile.id) else { throw LiveTVError.missingCredentials }
            return try StreamURLResolver.liveURL(for: channel, credentials: credentials)
        }
    }
}
