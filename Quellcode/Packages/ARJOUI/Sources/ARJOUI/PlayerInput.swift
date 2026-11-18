import SwiftUI

/// Tasten des Live-Players: Kanal, Gruppe, Zifferneingabe, Liste, Banner, Schliessen.
struct LiveKeys {
    var changeChannel: (Int) -> Void
    var changeGroup: (Int) -> Void
    var digit: (Int) -> Void
    var commit: () -> Void
    /// Esc: bricht eine laufende Eingabe ab, sonst schliesst es den Player.
    var escape: () -> Void
    var recall: () -> Void
    var showList: () -> Void
    var showInfo: () -> Void
}

#if !os(tvOS)
/// Bedienung des Players ohne sichtbare Tasten: Pfeiltasten (Mac, iPad mit Tastatur), Wischen und Doppeltippen links/rechts (iPhone).
/// Live: Hoch/Runter (bzw. Wischen) wechselt den Kanal, Links/Rechts die Gruppe, Ziffern wählen eine Nummer.
/// Film und Serie: Links/Rechts spult um 10 s.
private struct PlayerInput: ViewModifier {
    var live: LiveKeys?
    let seek: (Int) -> Void
    let reveal: () -> Void
    @FocusState private var isFocused: Bool
    @State private var width: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { width = max(proxy.size.width, 1) }
                    .onChange(of: proxy.size.width) { _, new in width = max(new, 1) }
            })
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear { isFocused = true }
            .onKeyPress(.upArrow) { handle { live?.changeChannel(-1) } }
            .onKeyPress(.downArrow) { handle { live?.changeChannel(1) } }
            .onKeyPress(.leftArrow) { handle { if let live { live.changeGroup(-1) } else { seek(-10) } } }
            .onKeyPress(.rightArrow) { handle { if let live { live.changeGroup(1) } else { seek(10) } } }
            .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                guard let live, let digit = press.characters.first?.wholeNumberValue else { return .ignored }
                return handle { live.digit(digit) }
            }
            .onKeyPress(.return) { guard let live else { return .ignored }; return handle { live.commit() } }
            .onKeyPress(.escape) { guard let live else { return .ignored }; return handle { live.escape() } }
            .onKeyPress(.space) { guard let live else { return .ignored }; return handle { live.showInfo() } }
            .onKeyPress(characters: CharacterSet(charactersIn: "lL"), phases: .down) { _ in
                guard let live else { return .ignored }
                return handle { live.showList() }
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "zZ"), phases: .down) { _ in
                guard let live else { return .ignored }
                return handle { live.recall() }
            }
            #if os(macOS)
            .onContinuousHover { _ in reveal() }
            #else
            .simultaneousGesture(TapGesture().onEnded { reveal() })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                seek(value.location.x < width / 2 ? -10 : 10)
                reveal()
            })
            .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { value in
                guard let live else { return }
                let t = value.translation
                // Wischen hoch = nächster Kanal; nach links = nächste Gruppe.
                if abs(t.height) >= abs(t.width) { live.changeChannel(t.height < 0 ? 1 : -1) } else { live.changeGroup(t.width < 0 ? 1 : -1) }
                reveal()
            })
            #endif
    }

    private func handle(_ action: () -> Void) -> KeyPress.Result {
        action(); reveal(); return .handled
    }
}

extension View {
    func playerInput(live: LiveKeys? = nil, seek: @escaping (Int) -> Void, reveal: @escaping () -> Void) -> some View {
        modifier(PlayerInput(live: live, seek: seek, reveal: reveal))
    }
}
#endif

/// Blendet die Kopfleiste nach `delay` ohne Aktivität aus; `reveal()` zeigt sie wieder.
@MainActor
@Observable
final class BarVisibility {
    private(set) var isVisible = true
    private var task: Task<Void, Never>?
    var isHeld = false

    func reveal(delay: Duration = .seconds(4)) {
        isVisible = true
        task?.cancel()
        task = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !self.isHeld else { return }
            self.isVisible = false
        }
    }
}
