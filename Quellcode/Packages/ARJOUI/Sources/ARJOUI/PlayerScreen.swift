import ARJOCore
import ARJOPlayer
import SwiftUI

struct PlayerScreen: View {
    @Bindable var model: LiveTVViewModel
    @Environment(OrganizationModel.self) private var organization
    @State private var showsChannelList = false
    @State private var showsNumberPad = false
    @State private var infoToken = 0
    @State private var bar = BarVisibility()

    private var keys: LiveKeys {
        LiveKeys(
            changeChannel: { model.playAdjacent(offset: $0) },
            changeGroup: { model.switchGroup(by: $0) },
            digit: { model.enterDigit($0) },
            commit: { Task { await model.commitNumber() } },
            escape: { if model.numberEntry.isEmpty { model.closePlayer() } else { model.cancelNumber() } },
            recall: { model.recallPreviousChannel() },
            showList: { showsChannelList.toggle() },
            showInfo: { infoToken += 1 }
        )
    }

    var body: some View {
        #if os(iOS) || os(tvOS)
        ZStack {
            Color.black.ignoresSafeArea()
            #if os(tvOS)
            PlaybackSurface(engine: model.engine, showsPlayerControls: false, fallbackControls: .none).ignoresSafeArea()
            if !showsChannelList, !showsNumberPad { remoteLayer }
            #else
            PlaybackSurface(engine: model.engine, showsPlayerControls: true, fallbackControls: .trackMenusOnly).ignoresSafeArea()
            #endif

            statusOverlay

            VStack {
                topBar.opacity(bar.isVisible ? 1 : 0).allowsHitTesting(bar.isVisible)
                Spacer()
            }
            .animation(.timingCurve(0.2, 0, 0, 1, duration: bar.isVisible ? 0.2 : 0.4), value: bar.isVisible)

            ZapOverlays(model: model, infoToken: infoToken)

            if showsNumberPad { NumberPad(model: model) { showsNumberPad = false } }

            if showsChannelList {
                HStack {
                    Spacer()
                    ChannelListPanel(model: model) { showsChannelList = false }
                }
            }
        }
        .onDisappear { model.closePlayer() }
        #if os(iOS)
        .playerInput(live: keys, seek: { model.engine.seek(bySeconds: $0) }, reveal: { bar.reveal(); infoToken += 1 })
        .onAppear { bar.reveal() }
        .onChange(of: showsChannelList) { _, shown in bar.isHeld = shown; if !shown { bar.reveal() } }
        #endif
        #elseif os(macOS)
        ZStack {
            Color.black
            PlaybackSurface(engine: model.engine, showsPlayerControls: true, fallbackControls: .trackMenusOnly)
            statusOverlay
            VStack {
                topBar.opacity(bar.isVisible ? 1 : 0).allowsHitTesting(bar.isVisible)
                Spacer()
            }
            .animation(.timingCurve(0.2, 0, 0, 1, duration: bar.isVisible ? 0.2 : 0.4), value: bar.isVisible)
            ZapOverlays(model: model, infoToken: infoToken)
            if showsNumberPad { NumberPad(model: model) { showsNumberPad = false } }
            if showsChannelList {
                HStack {
                    Spacer()
                    ChannelListPanel(model: model) { showsChannelList = false }
                }
            }
        }
        .onDisappear { model.closePlayer() }
        .playerInput(live: keys, seek: { model.engine.seek(bySeconds: $0) }, reveal: { bar.reveal() })
        .onAppear { bar.reveal() }
        #else
        Text("Wiedergabe wird auf diesem System nicht unterstützt.")
        #endif
    }

    #if os(iOS) || os(tvOS) || os(macOS)
    private var topBar: some View {
        HStack(spacing: 16) {
            #if os(iOS) || os(macOS)
            Button { model.closePlayer() } label: { Image(systemName: "xmark.circle.fill") }
                .accessibilityLabel("Schliessen")
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(topTitle).font(.arjo(.headline)).monospacedDigit().lineLimit(1)
                if let recording = model.catchupProgramme {
                    Text("Aufnahme: \(recording.title)").font(.arjo(.small)).lineLimit(1)
                } else if let channel = model.nowPlaying, let nowNext = model.epg.nowNext(for: channel) {
                    if let now = nowNext.now {
                        Text("Jetzt: \(now.title)").font(.arjo(.small)).lineLimit(1)
                    }
                    if let next = nowNext.next {
                        Text("Danach: \(next.title)").font(.arjo(.small)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
            }
            Spacer()
            #if os(iOS)
            CatchupControls(model: model)
            AirPlayButton().frame(width: 44, height: 44)
            #endif
            #if os(iOS) || os(macOS)
            VolumeControl(engine: model.engine)
            Button { showsNumberPad.toggle() } label: { Image(systemName: "circle.grid.3x3.fill") }
                .accessibilityLabel("Kanalnummer eingeben")
            Button { showsChannelList.toggle() } label: { Image(systemName: "list.bullet") }
                .accessibilityLabel("Senderliste")
            #endif
        }
        .font(.arjo(.title2))
        .foregroundStyle(.white)
        .padding()
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var topTitle: String {
        guard let channel = model.nowPlaying else { return "" }
        let name = organization.name(for: channel)
        return channel.number.map { "\($0)  \(name)" } ?? name
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch model.playback.status {
        case .buffering:
            ProgressView().scaleEffect(1.6)
        case .reconnecting(let attempt):
            VStack(spacing: 12) {
                ProgressView()
                Text("Verbindung wird neu aufgebaut (Versuch \(attempt))").font(.arjo(.body))
                #if os(iOS) || os(macOS)
                // Ohne laufendes Bild erscheinen die Bedienelemente nicht zuverlässig: hier immer ein Ausweg.
                Button("Schliessen") { model.closePlayer() }
                    .buttonStyle(PillButtonStyle())
                #endif
            }
            .padding(24)
            .glass(cornerRadius: Theme.tileRadius)
        case .failed(let message):
            VStack(spacing: 16) {
                Text(message)
                HStack(spacing: 12) {
                    Button("Erneut versuchen") { model.retry() }
                        .buttonStyle(PillButtonStyle(isProminent: true))
                    #if os(iOS) || os(macOS)
                    Button("Schliessen") { model.closePlayer() }
                        .buttonStyle(PillButtonStyle())
                    #endif
                }
            }
            .padding(24)
            .glass(cornerRadius: Theme.tileRadius)
        case .idle, .playing, .finished:
            EmptyView()
        }
    }
    #endif

    #if os(tvOS)
    /// Fängt die Siri Remote ab: Klick oben/unten wechselt den Kanal, links/rechts die Gruppe, OK zeigt das Banner,
    /// OK lang das Zahlenfeld, Wiedergabe/Pause die Senderliste, Menü das Menü (Filme, Serien …).
    private var remoteLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable()
            .onTapGesture { infoToken += 1 }
            .onLongPressGesture(minimumDuration: 0.6) { showsNumberPad = true }
            .onPlayPauseCommand { showsChannelList = true }
            .onExitCommand { model.closePlayer() }
            .onMoveCommand { direction in
                switch direction {
                case .up: model.playAdjacent(offset: -1)
                case .down: model.playAdjacent(offset: 1)
                case .left: model.switchGroup(by: -1)
                case .right: model.switchGroup(by: 1)
                @unknown default: break
                }
            }
            .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                guard let digit = press.characters.first?.wholeNumberValue else { return .ignored }
                model.enterDigit(digit)
                return .handled
            }
            .onKeyPress(.return) { Task { await model.commitNumber() }; return .handled }
    }
    #endif
}

#if os(iOS) || os(tvOS) || os(macOS)
private struct ChannelListPanel: View {
    let model: LiveTVViewModel
    @Environment(OrganizationModel.self) private var organization
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Text("Sender").font(.arjo(.headline))
                Spacer()
                #if os(tvOS)
                CatchupControls(model: model)
                #endif
                // Auf Apple TV ist die Fernbedienung beim Live-Bild für den Senderwechsel belegt: Ton und Untertitel liegen hier.
                TrackMenus(engine: model.engine)
            }
            .padding([.horizontal, .top], 24)
            channelList
        }
        .frame(width: 480)
        .glass(cornerRadius: Theme.largeRadius)
        .padding(12)
        #if os(tvOS)
        .onExitCommand { close() }
        #endif
    }

    private var channelList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.queue) { channel in
                        Button {
                            model.play(channel, in: model.queue)
                            close()
                        } label: {
                            HStack {
                                if let number = channel.number {
                                    Text(verbatim: String(number)).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 56, alignment: .trailing)
                                }
                                Text(organization.name(for: channel)).lineLimit(1)
                                Spacer()
                                if channel == model.nowPlaying { Image(systemName: "play.fill") }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .id(channel.id)
                    }
                }
                .padding(20)
            }
            .onAppear { proxy.scrollTo(model.nowPlaying?.id, anchor: .center) }
        }
    }
}
#endif

#if os(iOS) || os(tvOS)
/// «Von Anfang» für die laufende Sendung bzw. «Live» zurück, wenn gerade eine Aufnahme läuft.
private struct CatchupControls: View {
    let model: LiveTVViewModel

    var body: some View {
        if model.catchupProgramme != nil {
            Button { model.goLive() } label: { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
        } else if let channel = model.nowPlaying, let current = model.epg.nowNext(for: channel)?.now,
                  model.canCatchUp(channel, programme: current) {
            Button { Task { await model.playCatchup(current, on: channel) } } label: {
                Label("Von Anfang", systemImage: "gobackward")
            }
        }
    }
}
#endif

#if os(iOS) || os(macOS)
/// Stummschalten und Lautstärke des Players (Mac: mit Regler; iPhone und iPad haben die Lautstärketasten).
struct VolumeControl: View {
    let engine: HybridPlaybackEngine

    private var icon: String {
        engine.isMuted || engine.volume == 0 ? "speaker.slash.fill" : (engine.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
    }

    var body: some View {
        Button { engine.isMuted.toggle() } label: { Image(systemName: icon) }
            .accessibilityLabel(engine.isMuted ? "Ton einschalten" : "Ton ausschalten")
        #if os(macOS)
        Slider(value: Binding(get: { Double(engine.isMuted ? 0 : engine.volume) }, set: { engine.volume = Float($0); engine.isMuted = $0 == 0 }), in: 0...1)
            .frame(width: 110)
            .tint(.white)
            .accessibilityLabel("Lautstärke")
        #endif
    }
}
#endif
