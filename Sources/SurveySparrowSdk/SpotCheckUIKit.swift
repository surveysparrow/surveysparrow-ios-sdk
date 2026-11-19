import SwiftUI
import UIKit

// MARK: - UIKit entry
// Hosts the same SwiftUI SpotCheck engine once, in a transparent window above the app.

@available(iOS 15.0, *)
public final class SpotCheckUIKit {
    public static let shared = SpotCheckUIKit()

    private var window: SpotCheckPassThroughWindow?
    private var spotcheck: Spotcheck?
    private var sdk: SpotCheckSDK?
    private var alertWatch: Timer?

    private init() {}

    /// Call once, e.g. in `SceneDelegate.scene(_:willConnectTo:options:)`.
    public func attach(
        to windowScene: UIWindowScene,
        domainName: String,
        targetToken: String,
        userDetails: [String: Any] = [:],
        variables: [String: Any] = [:],
        customProperties: [String: Any] = [:],
        sparrowLang: String = "",
        surveyDelegate: SsSpotcheckDelegate = ssSurveyDelegate()
    ) {
        let view = Spotcheck(
            domainName: domainName,
            targetToken: targetToken,
            userDetails: userDetails,
            variables: variables,
            customProperties: customProperties,
            sparrowLang: sparrowLang,
            surveyDelegate: surveyDelegate
        )
        host(view, sdk: SpotCheckSDKManager.shared.sdk(for: targetToken), in: windowScene)
    }

    /// Values passed here are merged into the init values and kept for later calls.
    public func trackScreen(
        _ screen: String,
        userDetails: [String: Any] = [:],
        variables: [String: Any] = [:],
        customProperties: [String: Any] = [:]
    ) {
        observeVisibleNavigation()
        spotcheck?.TrackScreen(screen: screen, userDetails: userDetails, variables: variables, customProperties: customProperties)
    }

    public func trackEvent(onScreen screen: String, event: [String: Any]) {
        spotcheck?.TrackEvent(onScreen: screen, event: event)
    }

    public func closeSpotChecks() {
        spotcheck?.CloseSpotchecks()
    }

    /// Closes an open SpotCheck when this navigation controller pushes or pops.
    public func observeNavigation(of navigationController: UINavigationController) {
        SsNavigationListener.attach(to: navigationController, sdk: sdk)
    }

    /// Removes the overlay window.
    public func detach() {
        alertWatch?.invalidate()
        alertWatch = nil
        window?.isHidden = true
        window = nil
        spotcheck = nil
        sdk = nil
    }

    // 3.0.x apps (`isUIKitApp: true`): attach on the first track call.
    func attachIfNeeded(_ view: Spotcheck, sdk: SpotCheckSDK) {
        let attach = { [weak self] in
            guard let self else { return }
            if self.window == nil, let scene = Self.activeScene() {
                self.host(view, sdk: sdk, in: scene)
            }
            self.observeVisibleNavigation()
        }
        if Thread.isMainThread { attach() } else { DispatchQueue.main.async(execute: attach) }
    }

    /// Listens to the app's visible navigation controller so screen changes close an open SpotCheck.
    private func observeVisibleNavigation() {
        guard let sdk, let scene = window?.windowScene else { return }
        guard let nav = Self.topViewController(appWindow(in: scene)?.rootViewController)?.navigationController else { return }
        SsNavigationListener.attach(to: nav, sdk: sdk)
    }

    private func appWindow(in scene: UIWindowScene) -> UIWindow? {
        scene.windows.first { $0 !== window && $0.isKeyWindow } ?? scene.windows.first { $0 !== window }
    }

    /// While the app shows its own alert, sit below the app window so the alert stays on top, as in SwiftUI.
    private func stayBelowAppAlerts() {
        guard let window, let scene = window.windowScene else { return }
        let alertShown = Self.topViewController(appWindow(in: scene)?.rootViewController) is UIAlertController
        let level: UIWindow.Level = alertShown ? .normal - 1 : .normal + 1
        if window.windowLevel != level { window.windowLevel = level }
    }

    private static func topViewController(_ root: UIViewController?) -> UIViewController? {
        if let presented = root?.presentedViewController { return topViewController(presented) }
        if let nav = root as? UINavigationController { return topViewController(nav.visibleViewController) ?? nav }
        if let tab = root as? UITabBarController { return topViewController(tab.selectedViewController) ?? tab }
        return root
    }

    private func host(_ view: Spotcheck, sdk: SpotCheckSDK, in windowScene: UIWindowScene) {
        guard window == nil else { return }
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        let window = SpotCheckPassThroughWindow(windowScene: windowScene)
        window.sdk = sdk
        window.rootViewController = host
        window.backgroundColor = .clear
        // Above the app, below system alerts.
        window.windowLevel = .normal + 1
        window.isHidden = false

        self.window = window
        self.spotcheck = view
        self.sdk = sdk
        alertWatch = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.stayBelowAppAlerts()
        }
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

// MARK: - Pass-through window

/// Lets touches reach the app unless a SpotCheck card or button is under the finger.
@available(iOS 15.0, *)
final class SpotCheckPassThroughWindow: UIWindow {
    weak var sdk: SpotCheckSDK?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let (isVisible, isButton) = spotCheckState
        guard isVisible || isButton, let hit = super.hitTest(point, with: event), hit !== self else { return nil }
        // Card shown: its backdrop blocks the app, as in SwiftUI.
        if isVisible { return hit }
        // Button only: take the touch only where the button is drawn.
        return isDrawn(at: point) ? hit : nil
    }

    private var spotCheckState: (isVisible: Bool, isButton: Bool) {
        let state = sdk?.spotcheckStore.state["SpotCheckState"] as? [String: Any] ?? [:]
        let details = state["spotCheckDetails"] as? [String: Any] ?? [:]
        return (details["isVisible"] as? Bool ?? false, details["isSpotCheckButton"] as? Bool ?? false)
    }

    // Reads the overlay's pixel under the touch; transparent means nothing of ours is there.
    private func isDrawn(at point: CGPoint) -> Bool {
        guard let root = rootViewController?.view else { return false }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return true }
            let local = root.convert(point, from: self)
            context.translateBy(x: -local.x, y: -local.y)
            root.layer.render(in: context)
            return buffer[3] > 0
        }
        return drawn
    }
}
