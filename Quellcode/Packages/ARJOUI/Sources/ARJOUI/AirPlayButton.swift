#if os(iOS)
import AVKit
import SwiftUI

/// Systemtaste für die Wahl des AirPlay-Ziels (Apple TV, Lautsprecher, Fahrzeug mit AirPlay-Video). Die Wahl trifft immer der Nutzer.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(red: 252 / 255, green: 95 / 255, blue: 57 / 255, alpha: 1)
        view.prioritizesVideoDevices = true
        view.accessibilityLabel = String(localized: "AirPlay")
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
