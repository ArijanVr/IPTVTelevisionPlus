#if os(macOS)
import Sparkle

/// Selbst-Update für den Mac. Feed-URL und Schlüssel stehen in der Info.plist (SUFeedURL, SUPublicEDKey).
@MainActor
public final class AppUpdater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    public init() {}

    public func checkForUpdates() { controller.checkForUpdates(nil) }
}
#endif
