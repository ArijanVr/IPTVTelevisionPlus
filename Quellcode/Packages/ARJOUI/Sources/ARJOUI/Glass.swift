import SwiftUI

/// Liquid Glass ab iOS/tvOS 26, davor ein Material mit gleicher Form.
extension View {
    @ViewBuilder
    func glass(cornerRadius: CGFloat = Theme.tileRadius) -> some View {
        if #available(iOS 26, tvOS 26, macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, tvOS 26, macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Fläche für Inhalte (Zeilen, Listen). Liquid Glass gehört laut HIG nur auf Bedienelemente und Navigation über dem Inhalt;
    /// im Inhalt wäre es zudem teuer, weil jede Zeile beim Scrollen neu verwischt würde.
    func contentSurface(cornerRadius: CGFloat = Theme.tileRadius) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Zeigerreaktion auf iPad (Anheben bzw. Hervorheben); auf Mac und Apple TV ohne Wirkung.
    @ViewBuilder
    func pointerEffect(highlight: Bool = false) -> some View {
        #if os(iOS)
        hoverEffect(highlight ? .highlight : .lift)
        #else
        self
        #endif
    }
}
