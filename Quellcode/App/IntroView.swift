import ARJOUI
import SwiftUI

/// Startbildschirm laut IPTelevision+-Guide: Black, Icon mittig, Absender klein darunter. Kurz (0,7 s), damit Kanal 1 nicht warten muss; ohne Ton. Ein Tipp (bzw. Auswahl) überspringt ihn.
struct IntroView: View {
    private static let duration: Duration = .milliseconds(700)

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color(red: 9 / 255, green: 10 / 255, blue: 10 / 255).ignoresSafeArea()
            VStack(spacing: 28) {
                Image("IPTelevisionLockup")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 420)
                    .accessibilityHidden(true)
                Text("Ein Produkt von ARJO LAB")
                    .font(.arjo(.micro))
                    .foregroundStyle(Color(red: 217 / 255, green: 218 / 255, blue: 216 / 255))
            }
        }
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinished)
        #if os(tvOS)
        .focusable()
        .onPlayPauseCommand(perform: onFinished)
        .onExitCommand(perform: onFinished)
        #endif
        .accessibilityLabel("IP Television+")
        .task {
            do { try await Task.sleep(for: Self.duration) } catch { return }
            onFinished()
        }
    }
}
