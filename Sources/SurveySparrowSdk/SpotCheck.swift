import SwiftUI
import WebKit

// MARK: - Public API — Preserved from old architecture
// Example app uses: Spotcheck(domainName:, targetToken:, userDetails:, sparrowLang:, surveyDelegate:)
// Methods: .TrackScreen(screen:), .TrackEvent(onScreen:, event:), .navControllerFinder, .CloseSpotchecks()

@available(iOS 15.0, *)
public struct Spotcheck: View {
    @ObservedObject private var sdk: SpotCheckSDK

    private let domainName: String
    private let targetToken: String
    private let userDetails: [String: Any]
    private let variables: [String: Any]
    private let customProperties: [String: Any]
    private let sparrowLang: String
    private let surveyDelegate: SsSpotcheckDelegate

    public init(
        domainName: String,
        targetToken: String,
        userDetails: [String: Any] = [:],
        variables: [String: Any] = [:],
        customProperties: [String: Any] = [:],
        sparrowLang: String = "",
        surveyDelegate: SsSpotcheckDelegate = ssSurveyDelegate()
    ) {
        self.domainName = domainName
        self.targetToken = targetToken
        self.userDetails = userDetails
        self.variables = variables
        self.customProperties = customProperties
        self.sparrowLang = sparrowLang
        self.surveyDelegate = surveyDelegate
        self.sdk = SpotCheckSDKManager.shared.sdk(for: targetToken)
    }

    public func TrackScreen(screen: String) {
        sdk.trackScreen(screen)
    }

    public func TrackEvent(onScreen screen: String, event: [String: Any]) {
        sdk.trackEvent(screen, event: event)
    }

    public func CloseSpotchecks() {
        sdk.closeSpotCheck()
    }

    public var navControllerFinder: some View {
        NavControllerFinder(sdk: sdk)
            .frame(width: 0, height: 0)
    }

    public var body: some View {
        SpotCheckRootView(sdk: sdk)
            .onAppear {
                sdk.initialize(
                    domainName: domainName,
                    targetToken: targetToken,
                    userDetails: userDetails,
                    variables: variables,
                    customProperties: customProperties,
                    sparrowLang: sparrowLang,
                    delegate: surveyDelegate
                )
            }
    }
}

// MARK: - Default Delegate (no-op)

@available(iOS 13.0, *)
public class ssSurveyDelegate: SsSpotcheckDelegate {
    public init() {}
    public func handleSurveyResponse(response: [String: AnyObject]) async {}
    public func handleSurveyLoaded(response: [String: AnyObject]) async {}
    public func handlePartialSubmission(response: [String: AnyObject]) async {}
    public func handleCloseButtonTap() async {}
}

// MARK: - Color Extension

@available(iOS 13.0, *)
extension Color {
    init(hex: String) {
        // #RGB expands to #RRGGBB.
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        let scanner = Scanner(string: digits)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Navigation Controller Listener

@available(iOS 15.0, *)
private struct NavControllerFinder: UIViewControllerRepresentable {
    let sdk: SpotCheckSDK

    func makeUIViewController(context: Context) -> NavigationControllerSniffer {
        let vc = NavigationControllerSniffer()
        vc.sdk = sdk
        return vc
    }

    func updateUIViewController(_ uiViewController: NavigationControllerSniffer, context: Context) {}
}

@available(iOS 15.0, *)
final class NavigationControllerSniffer: UIViewController {
    weak var sdk: SpotCheckSDK?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard let nav = parent?.navigationController else { return }
        SsNavigationListener.attach(to: nav, sdk: sdk)
    }
}

/// Listens for pushes/pops without replacing the host app's own navigation delegate (calls are forwarded to it).
@available(iOS 15.0, *)
private final class SsNavigationListener: NSObject, UINavigationControllerDelegate {
    private static var associationKey = 0
    private weak var sdk: SpotCheckSDK?
    private weak var hostDelegate: UINavigationControllerDelegate?

    static func attach(to nav: UINavigationController, sdk: SpotCheckSDK?) {
        if let existing = nav.delegate as? SsNavigationListener {
            existing.sdk = sdk
            return
        }
        let listener = SsNavigationListener()
        listener.sdk = sdk
        listener.hostDelegate = nav.delegate
        // `delegate` is weak; the navigation controller keeps the listener alive.
        objc_setAssociatedObject(nav, &associationKey, listener, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        nav.delegate = listener
        if let host = listener.hostDelegate {
            // UIKit caches responds(to:) at assignment; re-assign when the host delegate goes away.
            let watcher = DeallocWatcher { [weak nav, weak listener] in
                guard let nav, let listener, nav.delegate === listener else { return }
                let reassign = {
                    nav.delegate = nil
                    nav.delegate = listener
                }
                if Thread.isMainThread { reassign() } else { DispatchQueue.main.async(execute: reassign) }
            }
            objc_setAssociatedObject(host, &DeallocWatcher.key, watcher, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        hostDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
        // Interactive swipe-back: close only if the swipe completes (a cancelled swipe stays on the screen).
        if let coordinator = navigationController.transitionCoordinator, coordinator.isInteractive {
            // Hold the revealed screen's trackScreen until the reset has run.
            let sdk = self.sdk
            sdk?.beginInteractiveNavigation()
            coordinator.notifyWhenInteractionChanges { context in
                if context.isCancelled {
                    sdk?.cancelInteractiveNavigation()
                } else {
                    sdk?.handleNavigationChange()
                }
            }
            return
        }
        sdk?.handleNavigationChange()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (hostDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        hostDelegate?.responds(to: aSelector) == true ? hostDelegate : super.forwardingTarget(for: aSelector)
    }
}

/// Runs a callback when its owner object is deallocated.
private final class DeallocWatcher: NSObject {
    static var key = 0
    private let onDealloc: () -> Void

    init(_ onDealloc: @escaping () -> Void) {
        self.onDealloc = onDealloc
    }

    deinit { onDealloc() }
}

// MARK: - Loader View

@available(iOS 13.0, *)
struct Loader: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 6.0, lineCap: .round, lineJoin: .round))
                .opacity(0.3)
                .foregroundColor(.black)
            Circle()
                .trim(from: 0.0, to: 0.7)
                .stroke(lineWidth: 6.0)
                .foregroundColor(.white)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)
                .onAppear { isAnimating = true }
        }
        .frame(width: 60, height: 60)
    }
}
