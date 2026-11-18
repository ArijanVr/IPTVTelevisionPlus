import ARJOCore
import SwiftUI

private struct SelectedProgramme: Identifiable {
    let channel: Channel
    let programme: EPGProgramme
    var id: String { channel.id + "@" + String(programme.start.timeIntervalSince1970) }
}

private struct GuideLoadKey: Hashable {
    let revision: Int
    let isUnlocked: Bool
    let organizationRevision: Int
}

struct GuideView: View {
    let live: LiveTVViewModel
    @Bindable var guide: GuideViewModel
    @State private var selected: SelectedProgramme?
    @State private var pending: PendingPlayback?
    @Environment(\.displayTimeZone) private var zone
    @Environment(ParentalControl.self) private var parental
    @Environment(OrganizationModel.self) private var organization

    #if os(tvOS)
    private let labelWidth: CGFloat = 260
    private let rowHeight: CGFloat = 92
    private let sidePadding: CGFloat = 48
    #else
    private let labelWidth: CGFloat = 110
    private let rowHeight: CGFloat = 56
    private let sidePadding: CGFloat = 12
    #endif

    var body: some View {
        VStack(spacing: 12) {
            controls
            if let message = guide.errorMessage {
                Text(message).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let timelineWidth = max(proxy.size.width - labelWidth - 2 * sidePadding, 240)
                ScrollView {
                    LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(guide.channels) { channel in
                                row(for: channel, timelineWidth: timelineWidth)
                            }
                        } header: {
                            timeHeader(timelineWidth: timelineWidth)
                        }
                    }
                    .overlay(alignment: .topLeading) { nowMarker(timelineWidth: timelineWidth) }
                    .padding(.horizontal, sidePadding)
                }
            }
        }
        .task(id: GuideLoadKey(revision: live.epg.revision, isUnlocked: parental.isUnlocked, organizationRevision: organization.revision)) {
            await guide.load()
        }
        .sheet(item: $selected, onDismiss: playPending) { item in
            ProgrammeDetail(
                channel: item.channel, programme: item.programme,
                canCatchUp: live.canCatchUp(item.channel, programme: item.programme),
                watchNow: {
                    pending = .live(item.channel)
                    selected = nil
                },
                catchUp: {
                    pending = .catchup(item.channel, item.programme)
                    selected = nil
                }
            )
        }
    }

    /// Erst nach dem Schliessen des Detailfensters abspielen, sonst geht die Vollbild-Anzeige verloren.
    private func playPending() {
        guard let action = pending else { return }
        pending = nil
        switch action {
        case .live(let channel): live.play(channel, in: guide.channels)
        case .catchup(let channel, let programme): Task { await live.playCatchup(programme, on: channel) }
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Menu {
                ForEach(guide.allowedGroups) { group in
                    Button(group.name) { Task { await guide.select(group) } }
                }
            } label: {
                Label(guide.selectedGroup?.name ?? String(localized: "Gruppe"), systemImage: "line.3.horizontal.decrease.circle")
            }
            Spacer()
            Button { Task { await guide.shiftWindow(hours: -3) } } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("3 Stunden zurück")
            Button("Jetzt") { Task { await guide.jumpToNow() } }
            Button { Task { await guide.shiftWindow(hours: 3) } } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("3 Stunden vor")
        }
        .padding(.horizontal, sidePadding)
        .padding(.top, 8)
    }

    private func timeHeader(timelineWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth, height: 1)
            ZStack(alignment: .topLeading) {
                ForEach(0..<6, id: \.self) { slot in
                    Text(Formatting.time(guide.windowStart.addingTimeInterval(Double(slot) * 1_800), in: zone))
                        .font(.arjo(.small))
                        .foregroundStyle(.secondary)
                        .offset(x: timelineWidth * CGFloat(slot) / 6)
                }
            }
            .frame(width: timelineWidth, height: 28, alignment: .topLeading)
        }
        .padding(.vertical, 4)
        .background { ThemeBackground() }
    }

    @ViewBuilder
    private func nowMarker(timelineWidth: CGFloat) -> some View {
        let offset = Date().timeIntervalSince(guide.windowStart) / GuideViewModel.windowLength
        if offset >= 0, offset <= 1 {
            Rectangle()
                .fill(.tint)
                .frame(width: 2)
                .offset(x: labelWidth + timelineWidth * offset)
                .allowsHitTesting(false)
        }
    }

    private func row(for channel: Channel, timelineWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button { live.play(channel, in: guide.channels) } label: {
                Text(verbatim: channel.number.map { "\($0)  \(organization.name(for: channel))" } ?? organization.name(for: channel))
                    .monospacedDigit()
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .frame(width: labelWidth, height: rowHeight, alignment: .leading)
            }
            .guideButtonStyle()

            ZStack(alignment: .topLeading) {
                ForEach(guide.programmes(for: channel), id: \.self) { programme in
                    cell(programme, in: channel, timelineWidth: timelineWidth)
                }
            }
            .frame(width: timelineWidth, height: rowHeight, alignment: .topLeading)
            .clipped()
        }
    }

    @ViewBuilder
    private func cell(_ programme: EPGProgramme, in channel: Channel, timelineWidth: CGFloat) -> some View {
        let length = GuideViewModel.windowLength
        let startX = max(programme.start.timeIntervalSince(guide.windowStart), 0) / length * timelineWidth
        let endX = min(programme.stop.timeIntervalSince(guide.windowStart), length) / length * timelineWidth
        let width = endX - startX
        if width >= 24 {
            Button { selected = SelectedProgramme(channel: channel, programme: programme) } label: {
                Text(programme.title)
                    .font(.arjo(.small))
                    .lineLimit(2)
                    .padding(6)
                    .frame(width: width - 3, height: rowHeight - 4, alignment: .topLeading)
                    .overlay {
                        if programme.isAiring(at: Date()) {
                            RoundedRectangle(cornerRadius: 6).stroke(.tint, lineWidth: 2)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if live.canCatchUp(channel, programme: programme) {
                            Image(systemName: "gobackward")
                                .font(.arjo(.small))
                                .foregroundStyle(.secondary)
                                .padding(4)
                                .accessibilityLabel("Aufnahme verfügbar")
                        }
                    }
            }
            .guideButtonStyle()
            .offset(x: startX)
        }
    }
}

private extension View {
    func guideButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(TileButtonStyle())
        #else
        buttonStyle(.plain)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        #endif
    }
}

private enum PendingPlayback {
    case live(Channel)
    case catchup(Channel, EPGProgramme)
}

private struct ProgrammeDetail: View {
    let channel: Channel
    let programme: EPGProgramme
    let canCatchUp: Bool
    let watchNow: () -> Void
    let catchUp: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayTimeZone) private var zone

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(programme.title).font(.arjo(.title2))
            Text("\(channel.name) · \(Formatting.time(programme.start, in: zone)) – \(Formatting.time(programme.stop, in: zone))")
                .foregroundStyle(.secondary)
            if let subtitle = programme.subtitle { Text(subtitle).font(.arjo(.headline)) }
            if let description = programme.description {
                ScrollView { Text(description).frame(maxWidth: .infinity, alignment: .leading) }
            }
            Spacer(minLength: 0)
            HStack {
                if programme.isAiring(at: Date()) {
                    Button("Jetzt ansehen", action: watchNow)
                }
                if canCatchUp {
                    Button(LocalizedStringKey(programme.isAiring(at: Date()) ? "Von Anfang ansehen" : "Aufnahme ansehen"), action: catchUp)
                }
                Button("Schliessen") { dismiss() }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
