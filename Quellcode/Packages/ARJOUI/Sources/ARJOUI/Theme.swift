import ARJOCore
import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Design-Tokens nach dem Brandguide IP Television+ V1.0 (14.11.2026): «Grau trägt. Glut zeigt.»
/// Hell und Dunkel folgen dem System. Graustufen tragen die Oberfläche, genau ein Akzent (Glut #FC5F39) zeigt:
/// Fortschritt, Fokusring, Status-Punkt und das «+» der Wortmarke. Nie als Fläche, nie als Text.
public enum Theme {
    // MARK: Palette
    /// Akzent Glut #FC5F39, in beiden Modi gleich.
    public static let signal = Color(hex: 0xFC5F39)

    /// --bg: Off-White bzw. Black (kein reines #FFF / #000).
    public static let background = Color.adaptive(light: 0xFDFDFC, dark: 0x090A0A)
    /// --surface: Karte, Sheet, ruhende Taste (hell Hairline-Grau, dunkel Graphite).
    public static let surface = Color.adaptive(light: 0xE9EAE8, dark: 0x2A2C2C)
    /// --grouped: Gruppenfläche, Seitenleiste, Kachel-Grund.
    public static let raised = Color.adaptive(light: 0xF0F0EE, dark: 0x1A1B1D)
    /// Menüfläche (entspricht surface).
    public static let elevated = surface
    /// --text: Black bzw. Off-White.
    public static let text = Color.adaptive(light: 0x090A0A, dark: 0xFDFDFC)
    /// --text-2: Medium Grey (5.06 : 1 auf Off-White) bzw. Light Grey auf Dunkel.
    public static let textSecondary = Color.adaptive(light: 0x6B6E6D, dark: 0xD9DAD8)
    /// --hairline: Trennlinie.
    public static let hairline = Color.adaptive(light: 0xD9DAD8, dark: 0x2A2C2C)
    /// --primary: Primärfläche «Abspielen» in Black (hell) bzw. Off-White (dunkel).
    public static let focusBackground = Color.adaptive(light: 0x090A0A, dark: 0xFDFDFC)
    /// Text auf `focusBackground`.
    public static let onFocus = Color.adaptive(light: 0xFDFDFC, dark: 0x090A0A)
    /// Ausgewählt: schwarz gefüllt (hell) bzw. Off-White gefüllt (dunkel), wie die Sheets im Guide.
    public static let selectedBackground = focusBackground
    public static let onSelected = onFocus
    /// Text auf Glut.
    public static let onAccent = Color(hex: 0x090A0A)
    /// --accent: Glut. Fortschritt, Fokusring, Live-Punkt, Titelpunkt, Fehler-Icon.
    public static let glut = signal
    /// Akzent als Text: nie Glut (3.02 : 1 reicht nicht für Text). Hinweise in Textfarbe.
    public static let glutText = text
    /// Fokusring auf Bildflächen: Black (hell) bzw. Off-White (dunkel).
    public static let ringOnPastel = Color.adaptive(light: 0x090A0A, dark: 0xFDFDFC)

    public static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x090A0A) : Color(hex: 0xFDFDFC) }

    // MARK: Radien (Brandguide S. 8): 6 Chip, 8 Steuerelement, 12 Karte, 20 Sheet
    public static let chipRadius: CGFloat = 6
    public static let fieldRadius: CGFloat = 8
    public static let tileRadius: CGFloat = 12
    public static let sheetRadius: CGFloat = 20
    public static let largeRadius: CGFloat = 20

    /// Fokus-Hebung: Fernseher 6 %, sonst 4 % (Brandguide S. 10 und 16).
    #if os(tvOS)
    public static let focusScale: CGFloat = 1.06
    #else
    public static let focusScale: CGFloat = 1.04
    #endif
    /// Fokusring: Signal 2 px, Abstand 2 px.
    public static let ringWidth: CGFloat = 2, ringGap: CGFloat = 2
    /// Mindest-Trefferfläche (iOS, macOS).
    public static let minHit: CGFloat = 44

    /// 4-px-Raster. Rand mobil 16, Tablet 32, Desktop 60. Apple TV: Safe Area 90 / 60 pt.
    public enum Layout {
        #if os(tvOS)
        public static let safeX: CGFloat = 90, safeY: CGFloat = 60, gridGap: CGFloat = 40, rowTitleGap: CGFloat = 24, sectionGap: CGFloat = 60
        #elseif os(macOS)
        public static let safeX: CGFloat = 60, safeY: CGFloat = 16, gridGap: CGFloat = 24, rowTitleGap: CGFloat = 8, sectionGap: CGFloat = 48
        #else
        public static let safeX: CGFloat = 16, safeY: CGFloat = 16, gridGap: CGFloat = 24, rowTitleGap: CGFloat = 8, sectionGap: CGFloat = 48
        #endif
    }

    /// Motion (Brandguide S. 16): Mikro 120, Kurz 200, Mittel 320, Lang 400 ms. Standard 0.2 / 0 / 0 / 1, kritisch gedämpft, kein Überschwingen.
    public enum Motion {
        public static let micro = 0.12, short = 0.20, medium = 0.32, long = 0.40
        public static func ui(_ duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
        public static func out(_ duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
        /// Kein Überschwingen (Brandguide S. 16): gleiche Kurve wie Standard.
        public static func spring(_ duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
        /// «Bewegung reduzieren»: Überblenden 160 ms, keine Feder.
        public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? { reduceMotion ? .easeInOut(duration: micro) : animation }
    }

    /// Standard für Steuerelemente: Textfarbe des Modus.
    public static let monochrome = text
}

/// Hintergrund der App: Black im dunklen Modus, Off-White im hellen.
struct ThemeBackground: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}

extension Color {
    /// Farbe, die dem Erscheinungsbild des Systems folgt.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
        #else
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(Color(hex: dark)) : NSColor(Color(hex: light)) })
        #endif
    }
}

// MARK: - Schrift (Geist, Geist Mono)

public enum ArjoTextStyle { case display, title1, title2, headline, body, bodyMedium, small, smallMedium, micro }

public extension Font {
    /// Skala aus dem Guide S. 7: Large Title 34, Title 1 28, Title 2 22, Headline 17 Medium, Body 17, Subhead 15, Micro 12 Mono.
    /// Apple TV 10-Fuss: Titel 48–60, Body 24–29, Kachel 24–28. iPhone, iPad und Mac skalieren mit Dynamic Type.
    static func arjo(_ style: ArjoTextStyle) -> Font {
        #if os(tvOS)
        let sizes: [ArjoTextStyle: CGFloat] = [.display: 60, .title1: 52, .title2: 44, .headline: 34, .body: 28, .bodyMedium: 28, .small: 24, .smallMedium: 24, .micro: 24]
        #else
        let sizes: [ArjoTextStyle: CGFloat] = [.display: 34, .title1: 28, .title2: 22, .headline: 17, .body: 17, .bodyMedium: 17, .small: 15, .smallMedium: 15, .micro: 12]
        #endif
        let size = sizes[style] ?? 17
        let name: String
        switch style {
        case .display, .title1, .title2, .headline, .bodyMedium, .smallMedium: name = "Geist-Medium"
        case .body, .small: name = "Geist-Regular"
        case .micro: name = "GeistMono-Regular"
        }
        let relative: Font.TextStyle
        switch style {
        case .display: relative = .largeTitle
        case .title1: relative = .title
        case .title2: relative = .title2
        case .headline, .bodyMedium: relative = .headline
        case .body: relative = .body
        case .small, .smallMedium: relative = .subheadline
        case .micro: relative = .caption
        }
        return .custom(name, size: size, relativeTo: relative)
    }
}

/// Registriert die mitgelieferten Schriften. Einmal beim Start aufrufen.
public enum BrandFonts {
    public static func register(in bundle: Bundle = .main) {
        for name in ["Geist-Regular", "Geist-Medium", "GeistMono-Regular"] {
            guard let url = bundle.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Fokus, Kacheln, Tasten

/// Fokus nach Guide S. 8 und 11: Ring in Signal-Orange, 2 pt breit, 2 pt Abstand, Skalierung bis 1.04.
/// Auf Bildflächen (`onPastel`) Ring in Black bzw. Off-White. Erscheint sofort, ohne Animation.
struct FocusLift<S: InsettableShape>: ViewModifier {
    let shape: S
    let isActive: Bool
    /// Wird nicht mehr gebraucht (der Fokus hat keinen Schatten); bleibt für bestehende Aufrufer.
    var drawsShadow = true
    var onPastel = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    shape.inset(by: -(Theme.ringGap + Theme.ringWidth / 2))
                        .stroke(onPastel ? Theme.ringOnPastel : Theme.signal, lineWidth: Theme.ringWidth)
                }
            }
    }
}

/// Kachel: Fokusring (`FocusLift`), 0.96 gedrückt. Bewegung reduzieren: nur Ring, Überblenden 160 ms.
struct TileButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, filled: filled)
    }

    private struct TileBody: View {
        let configuration: ButtonStyleConfiguration
        let filled: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let scale: CGFloat = configuration.isPressed ? 0.96 : (isFocused && !reduceMotion ? Theme.focusScale : 1)
            configuration.label
                .background { if filled { RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).fill(Theme.raised) } }
                .scaleEffect(scale)
                .modifier(FocusLift(shape: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous), isActive: isFocused))
                .animation(Theme.Motion.resolved(configuration.isPressed ? Theme.Motion.spring(Theme.Motion.short) : Theme.Motion.ui(Theme.Motion.short), reduceMotion: reduceMotion), value: scale)
                .animation(Theme.Motion.resolved(Theme.Motion.spring(Theme.Motion.short), reduceMotion: reduceMotion), value: isFocused)
        }
    }
}

/// Hauptaktion («Abspielen»): Pille in Black mit Off-White-Text (dunkel umgekehrt), Höhe 44.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration)
    }

    private struct PrimaryBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.arjo(.bodyMedium))
                .foregroundStyle(Theme.onFocus)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(minHeight: Theme.minHit)
                .background(Theme.focusBackground, in: Capsule())
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused && !reduceMotion ? Theme.focusScale : 1))
                .modifier(FocusLift(shape: Capsule(), isActive: isFocused))
                .animation(Theme.Motion.resolved(Theme.Motion.spring(Theme.Motion.short), reduceMotion: reduceMotion), value: isFocused)
        }
    }
}

/// Eingabefeld im Markenstil: Raised-Fläche. Auf Apple TV bleibt das System-Feld (Fokusring vom System).
private struct BrandFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content
            .font(.arjo(.body))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        #endif
    }
}

extension View {
    func brandField() -> some View { modifier(BrandFieldStyle()) }
}

// MARK: - Pillen und Titel

/// Pillen-Taste nach Guide S. 9: ruhend `surface`, fokussiert und Hauptaktion in `focusBackground`, Fokusring Signal,
/// gedrückt 0.96, nicht verfügbar 50 %. `isProminent` (Hauptaktion) zeigt immer die invertierte Fläche.
/// Der Zeiger (Mac, iPad) hellt die ruhende Fläche leicht auf.
struct PillButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, isProminent: isProminent)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let isProminent: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        private var inverted: Bool { isProminent || isFocused }

        var body: some View {
            configuration.label
                .font(.arjo(.bodyMedium))
                .lineLimit(1)
                .foregroundStyle(inverted ? Theme.onFocus : Theme.text)
                .padding(.horizontal, Self.horizontal)
                .padding(.vertical, Self.vertical)
                .frame(minHeight: Self.minHeight)
                .background {
                    Capsule().fill(inverted ? Theme.focusBackground : Theme.surface)
                        .overlay { Capsule().fill(Theme.text.opacity(isHovered && !inverted ? 0.08 : 0)) }
                }
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused && !reduceMotion ? Theme.focusScale : 1))
                .modifier(FocusLift(shape: Capsule(), isActive: isFocused))
                .animation(Theme.Motion.resolved(Theme.Motion.spring(Theme.Motion.short), reduceMotion: reduceMotion), value: isFocused)
                .animation(Theme.Motion.ui(Theme.Motion.micro), value: isHovered)
                #if !os(tvOS)
                .onHover { isHovered = $0 }
                #endif
                .contentShape(Capsule())
        }

        #if os(tvOS)
        // control.height 66 pt (HIG-Standard), Kapsel-Radius 33 pt.
        private static let horizontal: CGFloat = 32
        private static let vertical: CGFloat = 14
        private static let minHeight: CGFloat = 66
        #else
        private static let horizontal: CGFloat = 18
        private static let vertical: CGFloat = 9
        private static let minHeight: CGFloat = Theme.minHit
        #endif
    }
}

/// Titel mit dem Signal-Punkt am Ende, wie im Guide (Titel dürfen einen Punkt in Orange tragen).
struct BrandTitle: View {
    let text: String
    var style: ArjoTextStyle = .title1

    var body: some View {
        (Text(verbatim: text) + Text(verbatim: ".").foregroundStyle(Theme.glut))
            .font(.arjo(style))
    }
}

/// Kleine Überschrift in Geist Mono, Grossbuchstaben, gesperrt («NEUE STAFFEL»).
struct Eyebrow: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.arjo(.micro))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}
