import ARJOCore
import SwiftUI

/// Öffnet die Einstellungen als eigenes Blatt (gesetzt von `MainTabView`).
struct SettingsOpener {
    var open: @MainActor () -> Void = {}

    @MainActor func callAsFunction() { open() }
}

extension EnvironmentValues {
    @Entry var openSettingsSheet = SettingsOpener()
}

#if !os(tvOS)
/// Profil-Symbol oben rechts (iPhone, iPad im Tab-Modus) wie in der Apple-TV-App: öffnet die Einstellungen.
/// Schwebt als Bedienelement über dem Inhalt und trägt deshalb Liquid Glass.
struct ProfileButton: View {
    let profile: Profile
    @Environment(\.openSettingsSheet) private var openSettings

    var body: some View {
        Button { openSettings() } label: {
            Text(verbatim: String(profile.name.prefix(1)).uppercased())
                .font(.arjo(.bodyMedium))
                .frame(width: 28, height: 28)
        }
        .glassButtonStyle()
        .buttonBorderShape(.circle)
        .accessibilityLabel("Einstellungen, Quelle \(profile.name)")
    }
}

/// Marke oben in der Seitenleiste (iPad, Mac).
struct SidebarHeader: View {
    var body: some View {
        Image("IPTelevisionLockup")
            .resizable()
            .scaledToFit()
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityLabel("IP Television+")
    }
}

/// Fuss der Seitenleiste wie in der Apple-TV-App: aktive Quelle und Einstellungen als eigener Eintrag unten.
struct SidebarFooter: View {
    let profile: Profile
    /// Ablaufdatum des Abos, falls der Anbieter es nennt.
    var expiry: Date?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var expiryText: Text? {
        guard let expiry else { return nil }
        return expiry <= Date()
            ? Text("Abo abgelaufen")
            : Text("Gültig bis \(expiry.formatted(.dateTime.day().month().year()))")
    }

    private var expiryColor: Color {
        guard let expiry else { return .secondary }
        return expiry.timeIntervalSinceNow < 7 * 86_400 ? .red : .secondary
    }

    #if os(macOS)
    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: String(profile.name.prefix(1)).uppercased())
                .font(.arjo(.smallMedium))
                .foregroundStyle(Theme.onSelected)
                .frame(width: 26, height: 26)
                .background(Theme.selectedBackground, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: profile.name).font(.arjo(.smallMedium)).lineLimit(1)
                Text("Einstellungen").font(.arjo(.small)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                if let expiryText {
                    expiryText.font(.arjo(.micro)).foregroundStyle(expiryColor).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Theme.selectedBackground) : AnyShapeStyle(.primary.opacity(isHovered ? 0.08 : 0)))
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityLabel("Einstellungen, Quelle \(profile.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    #else
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(verbatim: String(profile.name.prefix(1)).uppercased())
                    .font(.arjo(.bodyMedium))
                    .foregroundStyle(Theme.onSelected)
                    .frame(width: 32, height: 32)
                    .background(Theme.selectedBackground, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: profile.name).font(.arjo(.smallMedium)).lineLimit(1)
                    Text("Einstellungen").font(.arjo(.micro)).foregroundStyle(.secondary)
                    if let expiryText {
                        expiryText.font(.arjo(.micro)).foregroundStyle(expiryColor).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(isSelected ? Theme.glutText : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.selectedBackground) : AnyShapeStyle(.primary.opacity(isHovered ? 0.08 : 0)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(",", modifiers: .command)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .accessibilityLabel("Einstellungen, Quelle \(profile.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    #endif
}

/// iPhone ab iOS 26: Tab-Leiste aus Liquid Glass, die beim Scrollen kleiner wird, und darüber der zuletzt gesehene
/// Sender als Zubehör (wie der Mini-Player in Musik). Davor und auf dem Mac bleibt die Systemleiste unverändert.
struct LiquidGlassTabBar: ViewModifier {
    let session: ProfileSession

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            if let channel = session.live.lastChannel, !session.parental.isLocked(.live, channel.groupName) {
                content
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory { NowPlayingAccessory(channel: channel, live: session.live) }
            } else {
                content.tabBarMinimizeBehavior(.onScrollDown)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS)
/// Zuletzt gesehener Sender über der Tab-Leiste: Logo, Name, laufende Sendung, Abspielen.
@available(iOS 26, *)
private struct NowPlayingAccessory: View {
    let channel: Channel
    let live: LiveTVViewModel
    @Environment(OrganizationModel.self) private var organization
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button { Task { await live.resumeLastChannel() } } label: {
            HStack(spacing: 10) {
                CachedImage(url: channel.logoURL, contentMode: .fit, maxPixel: 120) {
                    Image(systemName: "tv").foregroundStyle(.secondary)
                }
                .frame(width: 34, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: organization.name(for: channel)).font(.arjo(.smallMedium)).lineLimit(1)
                    if placement != .inline, let now = live.epg.nowNext(for: channel)?.now {
                        Text(verbatim: now.title).font(.arjo(.micro)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill")
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(organization.name(for: channel)) live ansehen")
    }
}
#endif
#endif

extension View {
    /// Spiegelt und verwischt ein Titelbild bis unter die Seitenleiste aus Liquid Glass (iPad, Mac ab 26).
    @ViewBuilder
    func extendsBeneathSidebar() -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
    }
}
