import UIKit

@MainActor final class OrientationController {
    private var requested: UIInterfaceOrientationMask = .portrait
    private static var pendingMask: UIInterfaceOrientationMask?
    private static weak var pendingScene: UIWindowScene?
    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
    func request(_ mask: UIInterfaceOrientationMask) { requested = mask; Self.apply(mask) }
    private static func apply(_ mask: UIInterfaceOrientationMask) {
        let changed = AppDelegate.orientationLock != mask
        AppDelegate.orientationLock = mask
        guard let scene = activeScene else { return }
        let orientation = scene.effectiveGeometry.interfaceOrientation
        let current = UIInterfaceOrientationMask(rawValue: 1 << orientation.rawValue)
        let needsRotation = orientation != .unknown && mask.intersection(current).isEmpty
        if !needsRotation && pendingScene === scene { pendingMask = nil; pendingScene = nil }
        guard changed || needsRotation else { return }
        // Geometry requests finish asynchronously; deduplicate while rotation is still in flight.
        if needsRotation && pendingScene === scene && pendingMask == mask { return }
        // Only the visible controller needs an update; updating both during dismissal races UIKit.
        var controller = scene.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed { controller = presented }
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if needsRotation {
            pendingScene = scene; pendingMask = mask
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak scene] _ in
                Task { @MainActor in if Self.pendingScene === scene && Self.pendingMask == mask { Self.pendingMask = nil; Self.pendingScene = nil } }
            }
        }
    }
    func toggle() { let landscape = Self.activeScene?.effectiveGeometry.interfaceOrientation.isLandscape ?? false; request(landscape ? .portrait : .landscape) }
    func resume() { Self.apply(requested) }
    static func restoreAppOrientation() { apply(.portrait) }
    func restore() { Self.restoreAppOrientation() }
}
