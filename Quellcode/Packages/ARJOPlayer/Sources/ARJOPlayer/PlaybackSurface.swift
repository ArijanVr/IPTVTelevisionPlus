import AVFoundation
import SwiftUI
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

/// Welche Bedienelemente die Fallback-Engine einblendet (der AVPlayer bringt seine eigenen mit).
public enum FallbackControls {
    /// Abspielen/Pause, Spulen, Zeitleiste, Audio und Untertitel.
    case full
    /// Nur Audio- und Untertitelwahl (Live auf iOS).
    case trackMenusOnly
    case none
}

/// Zeigt das Bild der gerade aktiven Engine.
public struct PlaybackSurface: View {
    private let engine: HybridPlaybackEngine
    private let showsPlayerControls: Bool
    private let fallbackControls: FallbackControls

    public init(engine: HybridPlaybackEngine, showsPlayerControls: Bool, fallbackControls: FallbackControls) {
        self.engine = engine
        self.showsPlayerControls = showsPlayerControls
        self.fallbackControls = fallbackControls
    }

    public var body: some View {
        switch engine.backend {
        case .avPlayer:
            PlayerSurface(player: engine.player, showsControls: showsPlayerControls, aspect: engine.aspect)
        case .fallback:
            #if canImport(VLCKitSPM)
            if let vlc = engine.fallbackEngine() as? VLCEngine {
                ZStack {
                    VLCSurface(engine: vlc, aspect: engine.aspect)
                    if fallbackControls != .none {
                        VLCControls(engine: vlc, tracksOnly: fallbackControls == .trackMenusOnly)
                    }
                }
            }
            #endif
        }
    }
}

#if canImport(VLCKitSPM)
/// Hält die Grösse bereit, damit «Füllen» das Bild auf das Seitenverhältnis der Anzeige zuschneiden kann.
#if os(macOS)
private final class VLCHostView: NSView {
    var onLayout: ((CGSize) -> Void)?

    override func layout() {
        super.layout()
        onLayout?(bounds.size)
    }
}

private struct VLCSurface: NSViewRepresentable {
    let engine: VLCEngine
    let aspect: PlayerAspect

    func makeNSView(context: Context) -> NSView {
        let view = VLCHostView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        engine.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let host = view as? VLCHostView else { return }
        host.onLayout = { [engine, aspect] size in engine.apply(aspect: aspect, viewSize: size) }
        engine.apply(aspect: aspect, viewSize: host.bounds.size)
    }
}
#else
private final class VLCHostView: UIView {
    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }
}

private struct VLCSurface: UIViewRepresentable {
    let engine: VLCEngine
    let aspect: PlayerAspect

    func makeUIView(context: Context) -> UIView {
        let view = VLCHostView()
        view.backgroundColor = .black
        engine.attach(to: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let host = view as? VLCHostView else { return }
        host.onLayout = { [engine, aspect] size in engine.apply(aspect: aspect, viewSize: size) }
        engine.apply(aspect: aspect, viewSize: host.bounds.size)
    }
}
#endif

private struct VLCControls: View {
    let engine: VLCEngine
    let tracksOnly: Bool
    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            gestureLayer
            if isVisible || engine.isPaused {
                VStack {
                    // Live: Die Kopfleiste des Players (Schliessen, Zahlenfeld, Senderliste) liegt oben rechts darüber; die Menüs
                    // sitzen darunter, sonst fängt die Leiste die Klicks ab und Ton/Untertitel lassen sich nicht wählen.
                    if tracksOnly { HStack { Spacer(); trackMenus } .padding(.horizontal).padding(.top, 76) }
                    Spacer()
                    if !tracksOnly { controlBar }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { flash() }
    }

    @ViewBuilder
    private var gestureLayer: some View {
        #if os(tvOS)
        if !tracksOnly {
            Button { isVisible ? hide() : flash() } label: {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .onMoveCommand { direction in
                switch direction {
                case .left: engine.seek(bySeconds: -10); flash()
                case .right: engine.seek(bySeconds: 10); flash()
                default: break
                }
            }
            .onPlayPauseCommand { engine.togglePause(); flash() }
        }
        #else
        Color.clear.contentShape(Rectangle()).onTapGesture { isVisible ? hide() : flash() }
        #endif
    }

    private var controlBar: some View {
        VStack(spacing: 12) {
            if engine.durationSeconds > 0 {
                seekBar
            }
            HStack(spacing: 24) {
                if engine.isSeekable {
                    Button { engine.seek(bySeconds: -10); flash() } label: { Image(systemName: "gobackward.10") }
                        .accessibilityLabel("10 Sekunden zurück")
                }
                Button { engine.togglePause(); flash() } label: {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(engine.isPaused ? "Abspielen" : "Pause")
                if engine.isSeekable {
                    Button { engine.seek(bySeconds: 10); flash() } label: { Image(systemName: "goforward.10") }
                        .accessibilityLabel("10 Sekunden vor")
                }
                Spacer()
                trackMenus
            }
            .font(.title2)
        }
        .padding()
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
    }

    private var seekBar: some View {
        HStack(spacing: 12) {
            Text(clock(engine.positionSeconds)).monospacedDigit().font(.caption)
            #if os(tvOS)
            ProgressView(value: min(engine.positionSeconds, engine.durationSeconds), total: engine.durationSeconds)
            .tint(Color(red: 252 / 255, green: 95 / 255, blue: 57 / 255))
            #else
            Slider(
                value: Binding(
                    get: { engine.positionSeconds / max(engine.durationSeconds, 1) },
                    set: { engine.seek(toFraction: $0); flash() }
                )
            )
            .tint(Color(red: 252 / 255, green: 95 / 255, blue: 57 / 255))
            #endif
            Text(clock(engine.durationSeconds)).monospacedDigit().font(.caption)
        }
    }

    private var trackMenus: some View {
        TrackMenus(
            audio: engine.audioTracks, subtitles: engine.subtitleTracks,
            selectAudio: { engine.selectAudioTrack($0) }, selectSubtitle: { engine.selectSubtitleTrack($0) }
        )
    }

    private func flash() {
        isVisible = true
        hideTask?.cancel()
        hideTask = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            hide()
        }
    }

    private func hide() {
        hideTask?.cancel()
        isVisible = false
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3_600, minutes = total % 3_600 / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
#endif

/// Nur das Bild, ohne Bedienelemente und ohne `AVPlayerViewController`: leicht genug für mehrere Bilder gleichzeitig (Multiview).
public struct VideoOnlySurface: View {
    private let engine: HybridPlaybackEngine

    public init(engine: HybridPlaybackEngine) {
        self.engine = engine
    }

    public var body: some View {
        switch engine.backend {
        case .avPlayer:
            PlayerLayerSurface(player: engine.player)
        case .fallback:
            #if canImport(VLCKitSPM)
            if let vlc = engine.fallbackEngine() as? VLCEngine {
                VLCSurface(engine: vlc, aspect: .fit)
            }
            #endif
        }
    }
}

#if os(macOS)
private final class PlayerLayerView: NSView {
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlayerLayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = PlayerLayerView()
        view.wantsLayer = true
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? PlayerLayerView)?.playerLayer.player = player
    }
}
#else
private final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlayerLayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        (view as? PlayerLayerView)?.playerLayer.player = player
    }
}
#endif

/// Audio- und Untertitelwahl als Menüs; erscheinen nur, wenn es etwas zu wählen gibt.
public struct TrackMenus: View {
    private let audio: [MediaTrack]
    private let subtitles: [MediaTrack]
    private let selectAudio: (Int) -> Void
    private let selectSubtitle: (Int?) -> Void

    public init(
        audio: [MediaTrack], subtitles: [MediaTrack],
        selectAudio: @escaping (Int) -> Void, selectSubtitle: @escaping (Int?) -> Void
    ) {
        self.audio = audio
        self.subtitles = subtitles
        self.selectAudio = selectAudio
        self.selectSubtitle = selectSubtitle
    }

    /// Menüs für die gerade aktive Engine.
    public init(engine: HybridPlaybackEngine) {
        self.init(
            audio: engine.audioTracks, subtitles: engine.subtitleTracks,
            selectAudio: { engine.selectAudioTrack($0) }, selectSubtitle: { engine.selectSubtitleTrack($0) }
        )
    }

    public var body: some View {
        if audio.count > 1 {
            Menu {
                ForEach(audio) { track in
                    Button { selectAudio(track.id) } label: {
                        if track.isSelected { Label(track.name, systemImage: "checkmark") } else { Text(track.name) }
                    }
                }
            } label: { Image(systemName: "speaker.wave.2") }
            .accessibilityLabel("Audiospur")
        }
        // VLC liefert «Deaktivieren» (Index -1) schon als Eintrag; die Aus-Zeile gibt es für alle Engines.
        let choices = subtitles.filter { $0.id >= 0 }
        if !choices.isEmpty {
            Menu {
                Button { selectSubtitle(nil) } label: {
                    if choices.allSatisfy({ !$0.isSelected }) { Label("Aus", systemImage: "checkmark") } else { Text("Aus") }
                }
                ForEach(choices) { track in
                    Button { selectSubtitle(track.id) } label: {
                        if track.isSelected { Label(track.name, systemImage: "checkmark") } else { Text(track.name) }
                    }
                }
            } label: { Image(systemName: "captions.bubble") }
            .accessibilityLabel("Untertitel")
        }
    }
}
