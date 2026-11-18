#if os(iOS)
import ARJOUI
import CarPlay
import UIKit

/// Verbindet die CarPlay-Szene mit dem `CarPlayCoordinator`.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated { CarPlayCoordinator.shared.connect(interfaceController) }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated { CarPlayCoordinator.shared.disconnect() }
    }
}
#endif
