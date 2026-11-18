import SwiftUI

/// Merkt sich das Bild des gerade fokussierten Inhalts für den unscharfen Hintergrund (Apple-TV-Stil).
@MainActor
@Observable
final class BackdropState {
    var url: URL?
}

struct BackdropView: View {
    @Environment(BackdropState.self) private var backdrop: BackdropState?

    var body: some View {
        ZStack {
            ThemeBackground()
            if let url = backdrop?.url {
                CachedImage(url: url, contentMode: .fill, maxPixel: 48, interpolation: .high) { Color.clear }
                    .opacity(0.4)
                    .transition(.opacity)
                    .id(url)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: backdrop?.url)
        .ignoresSafeArea()
    }
}

extension View {
    /// Unscharfer Hintergrund aus dem fokussierten Inhalt; nur auf Apple TV, wo es einen Fokus gibt.
    @ViewBuilder
    func focusBackdrop() -> some View {
        #if os(tvOS)
        background { BackdropView() }
        #else
        self
        #endif
    }

    /// Meldet das Bild dieser Kachel als Hintergrund, solange sie den Fokus hat.
    func reportsBackdrop(_ url: URL?) -> some View {
        modifier(BackdropReporter(url: url))
    }
}

private struct BackdropReporter: ViewModifier {
    let url: URL?
    @Environment(\.isFocused) private var isFocused
    @Environment(BackdropState.self) private var backdrop: BackdropState?

    func body(content: Content) -> some View {
        content.onChange(of: isFocused) { _, focused in
            if focused { backdrop?.url = url }
        }
    }
}
