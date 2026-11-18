import SwiftUI

/// Eine Kachel auf der Startseite der Einstellungen.
struct SettingsTileModel: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let destination: () -> AnyView

    init<D: View>(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder destination: @escaping () -> D) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destination = { AnyView(destination()) }
    }
}

/// Startseite der Einstellungen als Kachelraster (Brandguide S. 10 und 11): ruhige Graphite-Karten, Symbol links,
/// Titel und Untertitel, Pfeil rechts. Auf dem Fernseher führt der Fokusring (Glut) mit den Pfeiltasten durchs Raster.
struct SettingsHub: View {
    let tiles: [SettingsTileModel]

    #if os(tvOS)
    private let minimum: CGFloat = 480
    private let gap: CGFloat = 32
    #else
    private let minimum: CGFloat = 300
    private let gap: CGFloat = 12
    #endif

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: gap, alignment: .top)], alignment: .leading, spacing: gap) {
                ForEach(tiles) { tile in
                    NavigationLink {
                        tile.destination()
                    } label: {
                        SettingsTile(icon: tile.icon, title: tile.title, subtitle: tile.subtitle)
                    }
                    .settingsTileButtonStyle()
                }
            }
            .padding(.horizontal, Theme.Layout.safeX)
            .padding(.vertical, 24)
            #if !os(tvOS)
            .frame(maxWidth: 1200)
            #endif
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SettingsTile: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    #if os(tvOS)
    private let iconSize: CGFloat = 64, pad: CGFloat = 24
    #else
    private let iconSize: CGFloat = 40, pad: CGFloat = 14
    #endif

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: iconSize * 0.45, weight: .regular))
                .foregroundStyle(Theme.text)
                .frame(width: iconSize, height: iconSize)
                .background(Theme.background.opacity(0.6), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.arjo(.bodyMedium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle).font(.arjo(.small)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.arjo(.small)).foregroundStyle(Theme.textSecondary)
        }
        .padding(pad)
        .frame(maxWidth: .infinity, minHeight: iconSize + pad * 2, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration)
    }

    private struct TileBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            configuration.label
                .background(Theme.surface.opacity(isHovered ? 1 : 0.85), in: shape)
                .overlay { shape.strokeBorder(Theme.hairline, lineWidth: isFocused ? 0 : 1) }
                .scaleEffect(configuration.isPressed ? 0.98 : (isFocused && !reduceMotion ? Theme.focusScale : 1))
                .modifier(FocusLift(shape: shape, isActive: isFocused))
                .animation(Theme.Motion.resolved(Theme.Motion.ui(Theme.Motion.short), reduceMotion: reduceMotion), value: isFocused)
                #if !os(tvOS)
                .onHover { isHovered = $0 }
                #endif
                .contentShape(shape)
        }
    }
}

extension View {
    func settingsTileButtonStyle() -> some View { buttonStyle(SettingsTileButtonStyle()) }
}

/// «Ein Produkt von ARJO LAB» (Brandguide S. 5): Geist Mono, Versalien, gesperrt, Signet davor.
struct ArjoLabSender: View {
    var body: some View {
        HStack(spacing: 10) {
            ArjoLabSignet().frame(width: 16, height: 16)
            Text("Ein Produkt von ARJO LAB")
                .font(.arjo(.micro))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Signet der Dachmarke: schwarzer Grund, Glut-Punkt unten rechts.
struct ArjoLabSignet: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous).fill(Color(hex: 0x090A0A))
                Circle().fill(Theme.signal)
                    .frame(width: side * 0.29, height: side * 0.29)
                    .offset(x: side * 0.60, y: side * 0.60)
            }
            .frame(width: side, height: side)
        }
    }
}
