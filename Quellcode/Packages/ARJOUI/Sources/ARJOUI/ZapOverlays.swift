import ARJOCore
import SwiftUI

/// Kurz eingeblendete Anzeigen über dem Fernsehbild: Gruppen-Banner oben, Kanal-Banner unten, Zifferneingabe in der Mitte.
/// Nichts davon fängt Eingaben ab; alles verschwindet von selbst.
struct ZapOverlays: View {
    let model: LiveTVViewModel
    /// Wird von aussen hochgezählt (OK kurz, Leertaste, Tippen), um das Kanal-Banner auf Wunsch zu zeigen.
    let infoToken: Int
    @Environment(OrganizationModel.self) private var organization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsChannelBanner = false
    @State private var hideTask: Task<Void, Never>?

    private var fade: Animation? { reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.2) }

    var body: some View {
        ZStack {
            VStack {
                if let group = model.groupBanner {
                    GroupBanner(group: group, name: organization.name(forGroup: group.name, in: .live))
                        .transition(.opacity)
                }
                Spacer()
            }
            VStack {
                Spacer()
                if showsChannelBanner, let channel = model.nowPlaying {
                    ChannelBanner(
                        channel: channel, name: organization.name(for: channel),
                        nowNext: model.epg.nowNext(for: channel), isRecording: model.catchupProgramme != nil
                    )
                    .transition(.opacity)
                }
            }
            if !model.numberEntry.isEmpty {
                NumberEntryBadge(text: model.numberEntry).transition(.opacity)
            } else if let message = model.numberMessage {
                NumberMessageBadge(text: message).transition(.opacity)
            }
        }
        .padding(Theme.Layout.overlayInset)
        .animation(fade, value: model.groupBanner)
        .animation(fade, value: showsChannelBanner)
        .animation(fade, value: model.numberEntry)
        .animation(fade, value: model.numberMessage)
        .allowsHitTesting(false)
        .onChange(of: model.bannerToken) { reveal() }
        .onChange(of: infoToken) { reveal() }
        .onAppear { reveal() }
        .onDisappear { hideTask?.cancel() }
    }

    private func reveal() {
        showsChannelBanner = true
        hideTask?.cancel()
        hideTask = Task {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            showsChannelBanner = false
        }
    }
}

private extension Theme.Layout {
    static var overlayInset: CGFloat {
        #if os(tvOS)
        safeX
        #else
        24
        #endif
    }
}

private struct GroupBanner: View {
    let group: ChannelNavigator.GroupPosition
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: name).font(.arjo(.headline)).lineLimit(1)
            Text(verbatim: "·").foregroundStyle(.secondary)
            Text("\(group.position) von \(group.count)").font(.arjo(.body)).foregroundStyle(.secondary).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .glass(cornerRadius: Theme.sheetRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gruppe \(name), \(group.position) von \(group.count)")
    }
}

private struct ChannelBanner: View {
    let channel: Channel
    let name: String
    let nowNext: NowNext?
    let isRecording: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            if let number = channel.number {
                Text(verbatim: String(number))
                    .font(.arjo(.display))
                    .monospacedDigit()
                    .frame(minWidth: 120, alignment: .trailing)
            }
            CachedImage(url: channel.logoURL, contentMode: .fit, maxPixel: 240) { Image(systemName: "tv").foregroundStyle(.secondary) }
                .frame(width: 96, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name).font(.arjo(.headline)).lineLimit(1)
                if let now = nowNext?.now {
                    Text("Jetzt: \(now.title)").font(.arjo(.small)).lineLimit(1)
                    ProgressBar(programme: now)
                }
                if let next = nowNext?.next {
                    Text("Danach: \(next.title)").font(.arjo(.small)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(maxWidth: 1100)
        .glass(cornerRadius: Theme.sheetRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let number = channel.number { parts.append(String(localized: "Kanal \(number)")) }
        parts.append(name)
        if let now = nowNext?.now { parts.append(String(localized: "Jetzt: \(now.title)")) }
        return parts.joined(separator: ", ")
    }
}

private struct ProgressBar: View {
    let programme: EPGProgramme

    var body: some View {
        let span = max(programme.stop.timeIntervalSince(programme.start), 1)
        let value = min(max(Date().timeIntervalSince(programme.start) / span, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(Theme.glut).frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct NumberEntryBadge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.arjo(.display))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 36)
            .padding(.vertical, 16)
            .glass(cornerRadius: Theme.sheetRadius)
            .accessibilityLabel("Kanalnummer \(text)")
    }
}

private struct NumberMessageBadge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.arjo(.headline))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .glass(cornerRadius: 24)
    }
}

/// Zahlenfeld 3 × 4 für Fernbedienungen und Touch ohne Zifferntasten.
struct NumberPad: View {
    let model: LiveTVViewModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(verbatim: model.numberEntry.isEmpty ? "–" : model.numberEntry)
                .font(.arjo(.display)).monospacedDigit()
                .accessibilityLabel(model.numberEntry.isEmpty ? Text("Kanalnummer eingeben") : Text("Kanalnummer \(model.numberEntry)"))
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow { ForEach(1...3, id: \.self) { digitKey(row * 3 + $0) } }
                }
                GridRow {
                    Button { model.cancelNumber(); close() } label: { Image(systemName: "xmark").frame(width: 70, height: 36) }
                        .buttonStyle(PillButtonStyle())
                        .accessibilityLabel("Abbrechen")
                    digitKey(0)
                    Button { Task { await model.commitNumber(); close() } } label: { Image(systemName: "checkmark").frame(width: 70, height: 36) }
                        .buttonStyle(PillButtonStyle(isProminent: true))
                        .accessibilityLabel("Bestätigen")
                }
            }
        }
        .padding(32)
        .glass(cornerRadius: 32)
        #if os(tvOS)
        .onExitCommand { model.cancelNumber(); close() }
        #endif
    }

    private func digitKey(_ digit: Int) -> some View {
        Button { model.enterDigit(digit) } label: { Text(verbatim: String(digit)).font(.arjo(.title2)).monospacedDigit().frame(width: 70, height: 36) }
            .buttonStyle(PillButtonStyle())
    }
}
