import ARJOCore
import SwiftUI
import UniformTypeIdentifiers

/// Darstellung der Senderkacheln aus den Einstellungen (Namen anzeigen, Grösse).
struct ChannelTileStyle: Equatable {
    var showsNames = true
    var size: TileSize = .regular

    #if os(tvOS)
    private static let base = CGSize(width: 320, height: 180) // grid.col.16x9
    #else
    private static let base = CGSize(width: 176, height: 99)
    #endif

    /// Grösse der Logo-Fläche (16:9).
    var artworkSize: CGSize {
        CGSize(width: (Self.base.width * size.scale).rounded(), height: (Self.base.height * size.scale).rounded())
    }
}

extension EnvironmentValues {
    @Entry var channelTileStyle = ChannelTileStyle()
}

/// Senderkachel: das Logo füllt eine 16:9-Fläche auf einem Farbschimmer aus dem Logo selbst,
/// darunter (abschaltbar) Name und laufende Sendung. Der Fortschritt liegt als feine Linie am unteren Rand.
struct ChannelTile: View {
    let channel: Channel
    var nowNext: NowNext?
    /// Gesetzt, wenn sich die Kachel per Ziehen verschieben lässt: erhält die ID des darauf abgelegten Senders.
    var onDropChannel: ((String) -> Void)?
    let action: () -> Void
    @Environment(OrganizationModel.self) private var organization
    @Environment(MultiviewModel.self) private var multiview: MultiviewModel?
    @Environment(\.channelTileStyle) private var style

    var body: some View {
        let name = organization.name(for: channel)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ChannelArtwork(
                    logoURL: channel.logoURL,
                    name: name,
                    progress: nowNext?.now?.progress(at: Date()),
                    showsNameOnFocus: !style.showsNames
                )
                .frame(width: style.artworkSize.width, height: style.artworkSize.height)
                .reportsBackdrop(channel.logoURL)

                if style.showsNames {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: channel.number.map { "\($0)  \(name)" } ?? name)
                            .font(.arjo(.bodyMedium))
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(nowNext?.now?.title ?? " ")
                            .font(.arjo(.small))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: style.artworkSize.width, alignment: .leading)
                }
            }
        }
        .buttonStyle(ArtworkButtonStyle())
        .channelReorder(channel, name: name, onDrop: onDropChannel)
        .channelMenu(channel, organization: organization, multiview: multiview)
        .accessibilityLabel(channel.number.map { "\($0) \(name)" } ?? name)
        .accessibilityValue(nowNext?.now?.title ?? "")
    }
}

/// Logo-Fläche einer Senderkachel. Reagiert selbst auf Fokus (Apple TV) und Zeiger (Mac, iPad).
struct ChannelArtwork: View {
    let logoURL: URL?
    let name: String
    var progress: Double?
    var showsNameOnFocus = false
    var cornerRadius: CGFloat = Theme.tileRadius

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Winziges Logo, hochgezogen: weicher Farbschimmer in der Farbe des Senders.
                CachedImage(url: logoURL, contentMode: .fill, maxPixel: 24, interpolation: .high) { Color.clear }
                    .opacity(0.35)
                    .saturation(1.2)
                LinearGradient(
                    colors: [Color(hex: 0x2A2C2C), Color(hex: 0x1A1B1D)],
                    startPoint: .top, endPoint: .bottom
                )
                CachedImage(url: logoURL, contentMode: .fit, maxPixel: 400, interpolation: .high) {
                    Text(Self.initials(of: name))
                        .font(.custom("Geist-Medium", size: proxy.size.height * 0.34))
                        .foregroundStyle(Color(hex: 0xFDFDFC).opacity(0.9))
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, proxy.size.width * 0.14)
                .padding(.vertical, proxy.size.height * 0.16)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.raised)
        .overlay(alignment: .bottom) {
            if let progress, progress > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.18))
                        Rectangle().fill(Theme.glut).frame(width: proxy.size.width * min(progress, 1))
                    }
                }
                .frame(height: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .modifier(ArtworkFocus(cornerRadius: cornerRadius, caption: showsNameOnFocus ? name : nil))
    }

    /// «SRF 1» → «S1», «Das Erste» → «DE»: Ersatz, solange kein Logo da ist.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "TV" : letters.uppercased()
    }
}

/// Fokus nach Brandguide: Anheben und neutraler Schatten (`FocusLift`), nur auf der Bildfläche, nicht auf dem Text darunter.
struct ArtworkFocus: ViewModifier {
    var cornerRadius: CGFloat = Theme.tileRadius
    var caption: String?
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var isActive: Bool { isFocused || isHovered }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                if let caption, isActive {
                    Text(caption)
                        .font(.arjo(.smallMedium))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .modifier(FocusLift(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), isActive: isFocused, drawsShadow: false))
            .scaleEffect(isActive && !reduceMotion ? (isFocused ? Theme.focusScale : 1.03) : 1)
            .shadow(color: .black.opacity(isActive ? 0.5 : 0), radius: isFocused ? 22 : 12, y: isFocused ? 12 : 6)
            .animation(reduceMotion ? nil : Theme.Motion.ui(Theme.Motion.short), value: isActive)
            #if !os(tvOS)
            .onHover { isHovered = $0 }
            #endif
    }
}

/// Schaltfläche ohne eigenen Rahmen: Fokus und Zeiger zeigt die Bildfläche selbst (`ArtworkFocus`).
struct ArtworkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Ziehen und Ablegen

/// Kennung eines gezogenen Senders. Das Präfix trennt ihn von beliebigem Text aus anderen Apps.
enum ChannelDrag {
    static let prefix = "ch.arjo.iptelevision.channel:"
    static func payload(_ channel: Channel) -> String { prefix + channel.id }
    static func channelID(from payload: String) -> String? {
        payload.hasPrefix(prefix) ? String(payload.dropFirst(prefix.count)) : nil
    }
}

extension View {
    /// Sender per Ziehen an eine andere Stelle derselben Reihe verschieben (Mac, iPad, iPhone).
    /// Alternative ohne Ziehen: «Meine Listen» bzw. das Kontextmenü. Auf Apple TV ohne Wirkung.
    @ViewBuilder
    func channelReorder(_ channel: Channel, name: String, onDrop: ((String) -> Void)?) -> some View {
        #if os(tvOS)
        self
        #else
        if let onDrop {
            modifier(ChannelReorder(channel: channel, name: name, onDrop: onDrop))
        } else {
            self
        }
        #endif
    }
}

#if !os(tvOS)
/// Ablegen innerhalb derselben Reihe verschiebt (kein Kopieren-Zeichen), wie es die HIG für denselben Container vorsieht.
private struct ChannelDropDelegate: DropDelegate {
    let targetID: String
    @Binding var isTargeted: Bool
    let onDrop: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String, let id = ChannelDrag.channelID(from: payload), id != targetID else { return }
            Task { @MainActor in withAnimation(.smooth(duration: 0.3)) { onDrop(id) } }
        }
        return true
    }
}

private struct ChannelReorder: ViewModifier {
    let channel: Channel
    let name: String
    let onDrop: (String) -> Void
    @State private var isTargeted = false
    @Environment(\.channelTileStyle) private var style

    func body(content: Content) -> some View {
        content
            .draggable(ChannelDrag.payload(channel)) {
                ChannelArtwork(logoURL: channel.logoURL, name: name)
                    .frame(width: style.artworkSize.width, height: style.artworkSize.height)
                    .opacity(0.9)
            }
            .onDrop(of: [.plainText], delegate: ChannelDropDelegate(targetID: channel.id, isTargeted: $isTargeted, onDrop: onDrop))
            // Einfügemarke in Glut an der Stelle, an die der gezogene Sender kommt.
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Theme.glut)
                    .frame(width: 4, height: style.artworkSize.height)
                    .offset(x: -14)
                    .opacity(isTargeted ? 1 : 0)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}
#endif
