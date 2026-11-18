import ARJOCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension View {
    /// `fullScreenCover` gibt es auf macOS nicht; dort deckt die Ansicht das ganze Fenster ab.
    func playerCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        overlay {
            if isPresented.wrappedValue {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .onExitCommand { isPresented.wrappedValue = false }
            }
        }
        .toolbar(isPresented.wrappedValue ? .hidden : .automatic, for: .windowToolbar)
        .onChange(of: isPresented.wrappedValue) { _, presented in
            MacWindowFullScreen.set(presented)
        }
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}

extension View {
    /// Blatt auf dem Mac: höchstens so gross wie gewünscht, aber nie grösser als das Hauptfenster
    /// (rundum 40 pt Luft), damit es nicht über das Fenster hinausragt. `chrome` ist die Höhe, die macOS
    /// ausserhalb des Inhalts dazugibt (z. B. die Leiste mit «Fertig»).
    @ViewBuilder
    func fitsInMainWindow(width: CGFloat, height: CGFloat, chrome: CGFloat = 0) -> some View {
        #if os(macOS)
        let window = NSApp.mainWindow?.contentView?.bounds.size ?? CGSize(width: width + 80, height: height + 80 + chrome)
        frame(width: max(min(width, window.width - 80), 320), height: max(min(height, window.height - 80 - chrome), 280))
        #else
        self
        #endif
    }
}

enum Formatting {
    /// «1 Std. 45 Min.» in der Sprache des Geräts.
    static func duration(seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(max(seconds, 60)))
    }

    /// «1:05:09» oder «5:09».
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3_600, minutes = total % 3_600 / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func time(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    /// «Mo 20:15»
    static func weekdayAndTime(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).hour().minute())
    }

    static func rating(_ value: Double) -> String {
        "★ " + String(format: "%.1f", value)
    }
}

#if os(macOS)
/// Das Bild nutzt das echte Vollbild des Fensters (ohne Titelleiste) und gibt es beim Schliessen wieder frei – aber nur, wenn es selbst hineingewechselt hat.
@MainActor
private enum MacWindowFullScreen {
    private static var enteredByPlayer = false

    static func set(_ presented: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if presented, !isFullScreen {
            enteredByPlayer = true
            window.toggleFullScreen(nil)
        } else if !presented, enteredByPlayer, isFullScreen {
            enteredByPlayer = false
            window.toggleFullScreen(nil)
        } else if !presented {
            enteredByPlayer = false
        }
    }
}
#endif
