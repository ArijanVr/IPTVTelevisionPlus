import Foundation

public enum PlaybackEvent: Equatable, Sendable {
    case buffering
    case playing
    case failed(String)
    /// Nur bei Aufnahmen mit bekannter Länge (Filme, Episoden), nicht bei Live.
    case progress(position: TimeInterval, duration: TimeInterval)
    /// Wie `progress`, aber nach Pause oder Spulen: der Stand soll sofort gespeichert werden.
    case checkpoint(position: TimeInterval, duration: TimeInterval)
    case finished
}

public struct PlaybackRequest: Equatable, Sendable {
    public var url: URL
    public var startPosition: TimeInterval?

    public init(url: URL, startPosition: TimeInterval? = nil) {
        self.url = url
        self.startPosition = startPosition
    }
}

/// Abstraktion über AVPlayer und später die Fallback-Engine (VLCKit).
/// Der Controller kennt nur diese Schnittstelle.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var events: AsyncStream<PlaybackEvent> { get }
    /// Gewünschte Pufferlänge in Sekunden für den nächsten Start; 0 = Standard der Engine.
    var bufferDuration: TimeInterval { get set }
    /// Schaltet den Ton stumm (Multiview: nur ein Bild hat Ton).
    var isMuted: Bool { get set }
    /// Lautstärke 0 bis 1.
    var volume: Float { get set }
    /// Obergrenze der Bitrate in Bit/s für den nächsten Start; 0 = unbegrenzt (Multiview spart damit Leistung).
    var maxBitRate: Double { get set }
    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    func refreshTracks() async
    func selectAudioTrack(_ id: Int)
    func selectSubtitleTrack(_ id: Int?)
    func load(_ url: URL, startingAt position: TimeInterval?)
    func stop()
}

/// Eine wählbare Audio- oder Untertitelspur.
public struct MediaTrack: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let isSelected: Bool

    public init(id: Int, name: String, isSelected: Bool) {
        self.id = id
        self.name = name
        self.isSelected = isSelected
    }
}

public extension PlaybackEngine {
    /// Engines ohne einstellbaren Puffer (z. B. Test-Engines) ignorieren den Wert.
    var bufferDuration: TimeInterval {
        get { 0 }
        set {}
    }

    var isMuted: Bool {
        get { false }
        set {}
    }

    var volume: Float {
        get { 1 }
        set {}
    }

    var maxBitRate: Double {
        get { 0 }
        set {}
    }

    /// Standard: keine wählbaren Spuren.
    var audioTracks: [MediaTrack] { [] }
    var subtitleTracks: [MediaTrack] { [] }
    func refreshTracks() async {}
    func selectAudioTrack(_ id: Int) {}
    /// `nil` schaltet die Untertitel aus.
    func selectSubtitleTrack(_ id: Int?) {}
}

public enum PlayerAspect: Sendable {
    /// Ganzes Bild, bei Bedarf mit Rändern.
    case fit
    /// Füllt den Bildschirm, schneidet bei Bedarf ab.
    case fill
}
