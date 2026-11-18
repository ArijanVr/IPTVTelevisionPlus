import ARJOCore
import ARJOPlayer
import SwiftUI

struct MultiviewScreen: View {
    @Bindable var model: MultiviewModel
    let live: LiveTVViewModel
    @Environment(OrganizationModel.self) private var organization
    @Environment(ParentalControl.self) private var parental
    @Environment(\.channelTileStyle) private var tileStyle
    /// Bedienelemente blenden sich nach einer Weile aus, damit sie die Bilder nicht stören.
    @State private var showsControls = true
    @State private var activity = 0

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private static let hideDelay: Duration = .seconds(3)

    /// Der Zeitgeber startet neu bei jeder Bedienung und wenn die Senderwahl schliesst
    /// (sonst lief er während der offenen Wahl ab und die Leiste blieb für immer stehen).
    private struct HideTimer: Equatable {
        var activity: Int
        var isPicking: Bool
    }

    private func reveal() {
        showsControls = true
        activity += 1
    }

    private func pickChannel() {
        model.replacingSlotID = nil
        model.isPickingChannel = true
    }

    var body: some View {
        #if os(iOS) || os(tvOS) || os(macOS)
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if model.slots.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    grid(in: proxy.size)
                }
                .ignoresSafeArea(edges: .bottom)
            }

            controls
                .opacity(showsControls || model.slots.isEmpty ? 1 : 0)
                .allowsHitTesting(showsControls || model.slots.isEmpty)

            if let message = model.message {
                Text(message)
                    .font(.arjo(.smallMedium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glass(cornerRadius: Theme.tileRadius)
                    .padding(.top, 90)
                    .task(id: message) {
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        model.dismissMessage()
                    }
            }
        }
        .sheet(isPresented: $model.isPickingChannel) {
            MultiviewChannelPicker(model: model, live: live)
                .environment(organization)
                .environment(parental)
                .environment(\.channelTileStyle, tileStyle)
        }
        .simultaneousGesture(TapGesture().onEnded { reveal() })
        #if os(tvOS)
        .onMoveCommand { _ in reveal() }
        .onPlayPauseCommand { reveal() }
        #endif
        #if os(macOS)
        .onContinuousHover { _ in reveal() }
        #endif
        .task(id: HideTimer(activity: activity, isPicking: model.isPickingChannel)) {
            guard !model.isPickingChannel else { return }
            do { try await Task.sleep(for: Self.hideDelay) } catch { return }
            showsControls = false
        }
        .animation(.easeInOut(duration: 0.3), value: showsControls)
        .onDisappear { model.closeAll() }
        #else
        Text("Multiview wird auf diesem System nicht unterstützt.")
        #endif
    }

    #if os(iOS) || os(tvOS) || os(macOS)
    /// Leiste oben: Schliessen, Anzahl, Sender hinzufügen und Anordnung – auf Glas.
    private var controls: some View {
        HStack(spacing: 12) {
            #if os(iOS) || os(macOS)
            Button { model.closeAll() } label: { Image(systemName: "xmark") }
                .buttonStyle(PillButtonStyle())
                .accessibilityLabel("Schliessen")
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Multiview")
                Text("\(model.slots.count) von \(MultiviewModel.maxSlots) Sendern")
                    .font(.arjo(.smallMedium))
                    .foregroundStyle(.white)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 6)
            Spacer()
            Button(action: pickChannel) {
                Label("Sender hinzufügen", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(isProminent: true))
            .disabled(!model.canAddSlot)
            Menu {
                Picker("Anordnung", selection: $model.layout) {
                    ForEach(MultiviewLayout.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                Label(model.layout.title, systemImage: model.layout.symbol)
            }
            .menuStyle(.button)
            .buttonStyle(PillButtonStyle())
            .accessibilityLabel("Anordnung")
            .disabled(model.slots.count < 2)
        }
        // iPhone hochkant: nur Symbole, sonst werden die Beschriftungen zu «S…» gekürzt.
        .modifier(IconOnlyLabels(isActive: isCompact))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(cornerRadius: Theme.largeRadius)
        .padding(.horizontal, Self.edge)
        .padding(.top, Self.edge / 2)
        .environment(\.colorScheme, .dark)
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            BrandTitle(text: String(localized: "Mehrere Sender gleichzeitig"), style: .title2)
                .foregroundStyle(.white)
            Text("Bis zu vier Bilder. Nur eines hat Ton – wähle es mit einem Klick.")
                .font(.arjo(.body))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button(action: pickChannel) { Label("Sender wählen", systemImage: "plus") }
                .buttonStyle(PillButtonStyle(isProminent: true))
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if os(tvOS)
    private static let edge: CGFloat = 60
    #else
    private static let edge: CGFloat = 16
    #endif

    /// Nur so viele Felder wie laufende Sender: die Bilder füllen die ganze Fläche, ohne leere Plätze.
    private func grid(in size: CGSize) -> some View {
        let focus = model.slots.firstIndex { $0.id == model.audioSlotID } ?? 0
        let frames = model.layout.frames(count: model.slots.count, in: size, focus: focus)
        let isSingle = model.slots.count == 1
        let isPiP = model.layout.overlaps

        return ZStack(alignment: .topLeading) {
            ForEach(Array(model.slots.enumerated()), id: \.element.id) { index, slot in
                if frames.indices.contains(index) {
                    let isSmallPiP = isPiP && index != focus
                    MultiviewTile(model: model, slot: slot, showsLabel: showsControls || isSmallPiP, isFloating: isSmallPiP, showsAudioMarker: showsControls)
                        .clipShape(RoundedRectangle(cornerRadius: isSingle || (isPiP && !isSmallPiP) ? 0 : 10, style: .continuous))
                        .padding(isSingle || (isPiP && !isSmallPiP) ? 0 : 2)
                        .shadow(color: .black.opacity(isSmallPiP ? 0.6 : 0), radius: 18, y: 8)
                        .frame(width: frames[index].width, height: frames[index].height)
                        .offset(x: frames[index].minX, y: frames[index].minY)
                        .zIndex(isSmallPiP ? 1 : 0)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(.smooth(duration: 0.35), value: model.layout)
        .animation(.smooth(duration: 0.35), value: model.slots.map(\.id))
        .animation(.smooth(duration: 0.35), value: model.audioSlotID)
    }
    #endif
}

/// Beschriftete Tasten nur als Symbol (schmale Breite); die Beschriftung bleibt für VoiceOver erhalten.
private struct IconOnlyLabels: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive { content.labelStyle(.iconOnly) } else { content }
    }
}

#if os(iOS) || os(tvOS) || os(macOS)
private struct MultiviewTile: View {
    @Bindable var model: MultiviewModel
    let slot: MultiviewModel.Slot
    var showsLabel = true
    var isFloating = false
    /// Heller Rahmen um das Bild mit Ton (Brandguide: «Ausgewählt» neutral, Glut nur für Fortschritt/Live/Fehler): nur zusammen mit der Leiste, danach blendet er aus (Lautsprecher-Symbol bleibt Hinweis).
    var showsAudioMarker = true
    @Environment(OrganizationModel.self) private var organization

    private var hasAudio: Bool { model.audioSlotID == slot.id }

    var body: some View {
        Button {
            model.setAudio(slotID: slot.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.black
                // Die Videofläche ist eine UIKit/AppKit-Ansicht und schluckt sonst die Berührung:
                // Tippen aufs Bild erreichte die Taste nicht (Ton wechselte nicht).
                VideoOnlySurface(engine: slot.engine)
                    .allowsHitTesting(false)
                status
                HStack(spacing: 8) {
                    CachedImage(url: slot.channel.logoURL, contentMode: .fit, maxPixel: 120) { EmptyView() }
                        .frame(width: 28, height: 18)
                    Text(organization.name(for: slot.channel)).lineLimit(1)
                    Image(systemName: hasAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundStyle(hasAudio ? .white : .white.opacity(0.7))
                }
                .font(.arjo(.smallMedium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(isFloating ? 6 : 14)
                .opacity(showsLabel ? 1 : 0)
                .scaleEffect(isFloating ? 0.85 : 1, anchor: .bottomLeading)
            }
            .overlay {
                if hasAudio && model.slots.count > 1 && !(model.layout.overlaps && !isFloating) {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 3)
                        .opacity(showsAudioMarker ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasAudio ? Text("\(organization.name(for: slot.channel)), Ton an") : Text("\(organization.name(for: slot.channel)), stumm"))
        .contextMenu {
            Button { model.setAudio(slotID: slot.id) } label: { Label("Ton hier", systemImage: "speaker.wave.2") }
            Button {
                model.replacingSlotID = slot.id
                model.isPickingChannel = true
            } label: { Label("Anderen Sender wählen …", systemImage: "arrow.left.arrow.right") }
            Button(role: .destructive) { model.remove(slotID: slot.id) } label: { Label("Entfernen", systemImage: "xmark") }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch slot.playback.status {
        case .buffering, .reconnecting:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message).font(.arjo(.small)).multilineTextAlignment(.center).foregroundStyle(.white)
                Button("Erneut versuchen") { model.replace(slotID: slot.id, with: slot.channel) }
                    .buttonStyle(PillButtonStyle())
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle, .playing, .finished:
            EmptyView()
        }
    }
}

/// Senderwahl fürs Multiview: Suche, Quellen als Pillen (Favoriten, Zuletzt, Gruppen) und ein Raster aus Logo-Kacheln.
private struct MultiviewChannelPicker: View {
    private enum Source: Hashable {
        case favorites, recent
        case group(ChannelGroup)
    }

    @Bindable var model: MultiviewModel
    let live: LiveTVViewModel
    @Environment(OrganizationModel.self) private var organization
    @Environment(ParentalControl.self) private var parental
    @Environment(\.channelTileStyle) private var tileStyle
    @State private var source: Source?
    @State private var query = ""
    @State private var channels: [Channel] = []
    @State private var isLoading = false
    @State private var failed = false

    private var groups: [ChannelGroup] {
        organization.visible(live.groups, in: .live).filter { !parental.isLocked(.live, $0.name) }
    }

    private var favorites: [Channel] { allowed(organization.favorites) }

    private var sources: [Source] {
        var list: [Source] = []
        if !favorites.isEmpty { list.append(.favorites) }
        if live.lastChannel.map({ allowed([$0]).count == 1 }) == true { list.append(.recent) }
        return list + groups.map(Source.group)
    }

    private struct LoadKey: Hashable {
        let source: Source?
        let query: String
        let revision: Int
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if query.isEmpty { sourceBar }
                content
            }
            .navigationTitle(model.replacingSlotID == nil ? "Sender hinzufügen" : "Sender ersetzen")
            .searchable(text: $query, prompt: "Sender suchen")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { model.isPickingChannel = false }
                }
            }
            #endif
        }
        #if os(macOS)
        .fitsInMainWindow(width: 980, height: 720, chrome: 72)
        #endif
        .task(id: LoadKey(source: source, query: query, revision: organization.revision)) { await load() }
        .onAppear { if source == nil { source = sources.first } }
    }

    private var sourceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sources, id: \.self) { item in
                    Button { source = item } label: { Text(verbatim: title(item)) }
                        .buttonStyle(PillButtonStyle(isProminent: item == source))
                }
            }
            .padding(.horizontal, Self.margin)
            .padding(.vertical, 14)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var content: some View {
        let visible = organization.visible(channels).filter { !parental.isLocked(.live, $0.groupName) }
        if failed {
            message("Die Sender konnten nicht geladen werden.")
        } else if visible.isEmpty && !isLoading {
            message(query.isEmpty ? "Keine Sender in dieser Auswahl." : "Kein Sender gefunden.")
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: tileStyle.artworkSize.width, maximum: tileStyle.artworkSize.width * 1.3), spacing: 24)],
                    alignment: .leading, spacing: 24
                ) {
                    ForEach(visible) { channel in pickerTile(channel) }
                }
                .padding(.horizontal, Self.margin)
                .padding(.vertical, 16)
            }
        }
    }

    private func pickerTile(_ channel: Channel) -> some View {
        let isRunning = model.slots.contains { $0.channel.id == channel.id }
        let name = organization.name(for: channel)
        return Button { choose(channel) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ChannelArtwork(logoURL: channel.logoURL, name: name)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if isRunning {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.arjo(.headline))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color(hex: 0x090A0A), Theme.glut)
                                .padding(8)
                        }
                    }
                Text(name).font(.arjo(.smallMedium)).lineLimit(1)
            }
            .opacity(isRunning ? 0.5 : 1)
        }
        .buttonStyle(ArtworkButtonStyle())
        .disabled(isRunning)
        .accessibilityLabel(name)
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.arjo(.body))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
    }

    private func title(_ source: Source) -> String {
        switch source {
        case .favorites: String(localized: "Favoriten")
        case .recent: String(localized: "Zuletzt gesehen")
        case .group(let group): organization.name(forGroup: group.name, in: .live)
        }
    }

    private func allowed(_ channels: [Channel]) -> [Channel] {
        channels.filter { !organization.isHidden($0) && !parental.isLocked(.live, $0.groupName) }
    }

    private func load() async {
        failed = false
        if !query.isEmpty {
            // Kurz warten, damit nicht jeder Tastendruck eine Suche startet.
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            if !query.isEmpty {
                channels = try await live.searchChannels(query)
                return
            }
            switch source {
            case .favorites: channels = favorites
            case .recent: channels = live.lastChannel.map { [$0] } ?? []
            case .group(let group): channels = try await live.channels(in: group)
            case nil: channels = []
            }
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }

    private func choose(_ channel: Channel) {
        if let slotID = model.replacingSlotID {
            model.replace(slotID: slotID, with: channel)
        } else {
            model.add(channel)
        }
        model.replacingSlotID = nil
        model.isPickingChannel = false
    }

    #if os(tvOS)
    private static let margin: CGFloat = 60
    #else
    private static let margin: CGFloat = 24
    #endif
}
#endif
