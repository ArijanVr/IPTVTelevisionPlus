#if os(iOS) || os(tvOS)
import AVKit
import SwiftUI

/// Zeigt einen `AVPlayer` im System-Player. Auf iOS ist Bild-in-Bild eingeschaltet.
public struct PlayerSurface: UIViewControllerRepresentable {
    private let player: AVPlayer
    private let showsControls: Bool
    private let aspect: PlayerAspect

    public init(player: AVPlayer, showsControls: Bool, aspect: PlayerAspect = .fit) {
        self.player = player
        self.showsControls = showsControls
        self.aspect = aspect
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.videoGravity = aspect == .fill ? .resizeAspectFill : .resizeAspect
        #if os(iOS)
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        return controller
    }

    public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.videoGravity = aspect == .fill ? .resizeAspectFill : .resizeAspect
    }
}
#endif

#if os(macOS)
import AVKit
import SwiftUI

/// Zeigt einen `AVPlayer` im System-Player (macOS).
public struct PlayerSurface: NSViewRepresentable {
    private let player: AVPlayer
    private let showsControls: Bool
    private let aspect: PlayerAspect

    public init(player: AVPlayer, showsControls: Bool, aspect: PlayerAspect = .fit) {
        self.player = player
        self.showsControls = showsControls
        self.aspect = aspect
    }

    public func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        configure(view)
        return view
    }

    public func updateNSView(_ view: AVPlayerView, context: Context) {
        configure(view)
    }

    private func configure(_ view: AVPlayerView) {
        view.player = player
        view.controlsStyle = showsControls ? .floating : .none
        view.videoGravity = aspect == .fill ? .resizeAspectFill : .resizeAspect
    }
}
#endif
