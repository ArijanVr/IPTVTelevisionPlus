import ARJOCore
import ARJOPlayer
import SwiftUI

struct VODPlayerScreen: View {
    let model: VODPlayerModel
    @State private var bar = BarVisibility()

    var body: some View {
        #if os(iOS) || os(tvOS)
        ZStack {
            Color.black.ignoresSafeArea()
            PlaybackSurface(engine: model.engine, showsPlayerControls: true, fallbackControls: .full).ignoresSafeArea()
            statusOverlay
            upNextOverlay
            #if os(iOS)
            VStack {
                HStack(spacing: 12) {
                    Button { model.close() } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Schliessen")
                    Text(model.nowPlaying?.title ?? "").font(.arjo(.headline)).lineLimit(1)
                    Spacer()
                    VolumeControl(engine: model.engine)
                }
                .font(.arjo(.title2))
                .foregroundStyle(.white)
                .padding()
                .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
            }
            .opacity(bar.isVisible ? 1 : 0).allowsHitTesting(bar.isVisible)
            .animation(.timingCurve(0.2, 0, 0, 1, duration: bar.isVisible ? 0.2 : 0.4), value: bar.isVisible)
            #endif
        }
        .onDisappear { model.close() }
        #if os(iOS)
        .playerInput(seek: { model.engine.seek(bySeconds: $0) }, reveal: { bar.reveal() })
        .onAppear { bar.reveal() }
        #endif
        #elseif os(macOS)
        ZStack {
            Color.black
            PlaybackSurface(engine: model.engine, showsPlayerControls: true, fallbackControls: .full)
            statusOverlay
            upNextOverlay
            VStack {
                HStack(spacing: 12) {
                    Button { model.close() } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Schliessen")
                    Text(model.nowPlaying?.title ?? "").font(.arjo(.headline)).lineLimit(1)
                    Spacer()
                    VolumeControl(engine: model.engine)
                }
                .font(.arjo(.title2))
                .foregroundStyle(.white)
                .padding()
                .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
            }
            .opacity(bar.isVisible ? 1 : 0).allowsHitTesting(bar.isVisible)
            .animation(.timingCurve(0.2, 0, 0, 1, duration: bar.isVisible ? 0.2 : 0.4), value: bar.isVisible)
        }
        .onDisappear { model.close() }
        .playerInput(seek: { model.engine.seek(bySeconds: $0) }, reveal: { bar.reveal() })
        .onAppear { bar.reveal() }
        #else
        Text("Wiedergabe wird auf diesem System nicht unterstützt.")
        #endif
    }

    #if os(iOS) || os(tvOS) || os(macOS)
    @ViewBuilder
    private var upNextOverlay: some View {
        if let next = model.upNext {
            VStack {
                Spacer()
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Als Nächstes").font(.arjo(.small)).foregroundStyle(.secondary)
                        Text(next.title).font(.arjo(.headline)).lineLimit(1)
                        if let subtitle = next.subtitle { Text(subtitle).font(.arjo(.small)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    Button("Jetzt abspielen") { Task { await model.playUpNext() } }
                    Button("Abbrechen") { model.close() }
                }
                .padding(20)
                .glass(cornerRadius: Theme.tileRadius)
                .padding(32)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
            }
            .padding(24)
            .glass(cornerRadius: Theme.tileRadius)
        case .failed(let message):
            VStack(spacing: 16) {
                Text(message).multilineTextAlignment(.center)
                Button("Erneut versuchen") { Task { await model.retry() } }
            }
            .padding(24)
            .glass(cornerRadius: Theme.tileRadius)
            .padding(32)
        case .idle, .playing, .finished:
            EmptyView()
        }
    }
    #endif
}
