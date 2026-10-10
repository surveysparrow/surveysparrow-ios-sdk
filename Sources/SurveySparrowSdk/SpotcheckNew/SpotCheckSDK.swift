import Combine
import Foundation
import SwiftUI
import WebKit

@available(iOS 15.0, *)
private struct PendingTrackScreenRequest {
    let screen: String
    let variables: [String: Any]
    let customProperties: [String: Any]
    let userDetails: [String: Any]
}

// MARK: - SpotCheckSDKManager

@available(iOS 15.0, *)
final class SpotCheckSDKManager {
    static let shared = SpotCheckSDKManager()
    private var sdks: [String: SpotCheckSDK] = [:]
    private let lock = NSLock()

    func sdk(for token: String) -> SpotCheckSDK {
        lock.lock()
        defer { lock.unlock() }

        if let existing = sdks[token] {
            return existing
        }
        let newSDK = SpotCheckSDK()
        sdks[token] = newSDK
        return newSDK
    }
}

// MARK: - SpotCheckSDK — Central Orchestrator

@available(iOS 15.0, *)
final class SpotCheckSDK: ObservableObject {
    /// Backend page script from init config; nil keeps the built-in one.
    var remoteWebViewScript: String?
    let spotcheckStore: SpotCheckStateStore
    let functionStore: FunctionStore
    let componentStore: ComponentStore
    let executeBridge: ExecuteBridge
    let listenerBridge: ListenerBridge

    private let sentry: SentryAdapter
    private var classicWebView: WKWebView?
    private var chatWebView: WKWebView?

    /// SwiftUI can dismantle `UIViewRepresentable` on state merges (e.g. RESET_STATE). Pool detached views; `makeUIView` dequeues and rewires coordinators.
    private var pooledClassicWebView: WKWebView?
    private var pooledChatWebView: WKWebView?

    @Published var wrapperStyles: [String: Any] = [:]
    @Published var closeButtonStyles: [String: Any] = [:]
    @Published var spotCheckButtonStyles: [String: Any] = [:]

    /// `true` after fetch + `functionStore`/`componentStore` load + `initializeSpotcheckComponent` succeeds.
    private var spotcheckInitializationComplete = false
    private var spotcheckInitializationFailed = false
    /// SwiftUI calls onAppear repeatedly; only the first call (or a retry after failure) initializes.
    private var spotcheckInitializationStarted = false
    private let pendingTrackLock = NSLock()
    private var pendingTrackScreens: [PendingTrackScreenRequest] = []
    /// Set when `handleNavigationChange` runs; `trackScreen` is deferred until unmount + `handleNavigationChange` finish.
    private var navigationResetInProgress = false
    private var deferredTrackScreensAfterNavigation: [PendingTrackScreenRequest] = []

    private var pendingTrackEvents: [(String, [String: Any])] = []
    /// Latest params from an initialize() made while the first is in flight; re-applied after init.
    private var latestInitParams: [String: Any]?
    /// Re-runs the last initialize(); a failed init (e.g. offline) is retried on the next track call.
    private var retryInitialization: (() -> Void)?
    private var lastInitAttempt = Date.distantPast
    private static let initRetryGap: TimeInterval = 10

    init() {
        self.spotcheckStore = SpotCheckStateStore()
        self.functionStore = FunctionStore()
        self.componentStore = ComponentStore()
        self.listenerBridge = ListenerBridge(delegate: nil)
        self.sentry = SentryAdapter(domainName: { [weak spotcheckStore] in
            let state = spotcheckStore?.getState() ?? [:]
            let scState = state["SpotCheckState"] as? [String: Any] ?? [:]
            let params = scState["params"] as? [String: Any] ?? [:]
            return params["domainName"] as? String ?? ""
        })
        self.executeBridge = ExecuteBridge(spotcheckStore: spotcheckStore, functionStore: functionStore, sentry: sentry)
        self.sentry.executeBridge = self.executeBridge
        executeBridge.setListener(listenerBridge)
        executeBridge.onWebViewInject = { [weak self] target, script in
            self?.injectIntoWebView(target: target, script: script)
        }

        setupStateObservers()
    }

    // MARK: - Public API

    func initialize(
        domainName: String,
        targetToken: String,
        userDetails: [String: Any] = [:],
        variables: [String: Any] = [:],
        customProperties: [String: Any] = [:],
        sparrowLang: String = "",
        delegate: SsSpotcheckDelegate? = nil
    ) {
        listenerBridge.delegate = delegate

        pendingTrackLock.lock()
        if spotcheckInitializationStarted {
            // Legacy: each Spotcheck used its own details; take the latest.
            let latest: [String: Any] = [
                "userDetails": userDetails,
                "variables": variables,
                "customProperties": customProperties,
            ]
            if !spotcheckInitializationComplete { latestInitParams = latest }
            pendingTrackLock.unlock()
            spotcheckStore.dispatch(["params": latest])
            return
        }
        spotcheckInitializationStarted = true
        spotcheckInitializationFailed = false
        lastInitAttempt = Date()
        retryInitialization = { [weak self] in
            self?.initialize(
                domainName: domainName,
                targetToken: targetToken,
                userDetails: userDetails,
                variables: variables,
                customProperties: customProperties,
                sparrowLang: sparrowLang,
                delegate: delegate
            )
        }
        pendingTrackLock.unlock()

        let userAgent = buildUserAgent()
        let visitor = buildVisitorInfo()

        spotcheckStore.dispatch([
            "params": [
                "domainName": domainName,
                "targetToken": targetToken,
                "userDetails": userDetails,
                "variables": variables,
                "customProperties": customProperties,
                "visitor": visitor,
                "framework": "ios",
                "userAgent": userAgent,
            ],
        ])

        Task {
            do {
                let api = SpotCheckAPI(domainName: domainName)
                let response = try await api.fetchInitData()

                await MainActor.run {
                    functionStore.load(from: response)
                    componentStore.load(from: response)
                    let script = (response["config"] as? [String: Any])?["webViewScript"] as? String
                    self.remoteWebViewScript = (script?.isEmpty == false) ? script : nil
                }

                await executeBridge.execute("initializeSpotcheckComponent", params: [
                    "domainName": domainName,
                    "targetToken": targetToken,
                    "userDetails": userDetails,
                    "variables": variables,
                    "customProperties": customProperties,
                    "framework": "ios",
                    "sdkVersion": ExecuteBridge.spotcheckSdkVersion,
                    "device": buildDeviceFacts(),
                ])

                await MainActor.run {
                    // initializeSpotcheckComponent used the first call's params; re-apply the latest.
                    if let latest = self.completeInitialization() {
                        self.spotcheckStore.dispatch(["params": latest])
                    }
                }
                flushPendingTrackScreens()
                flushPendingTrackEvents()
            } catch {
                sentry.captureP0Error(error, "SPOTCHECK_INITIALIZATION", ["action": "initialize"])
                self.markInitializationFailed()
            }
        }
    }

    // Sync helpers: NSLock can't be used directly in async contexts.
    private func completeInitialization() -> [String: Any]? {
        pendingTrackLock.lock()
        defer { pendingTrackLock.unlock() }
        spotcheckInitializationComplete = true
        let latest = latestInitParams
        latestInitParams = nil
        return latest
    }

    private func markInitializationFailed() {
        pendingTrackLock.lock()
        defer { pendingTrackLock.unlock() }
        spotcheckInitializationFailed = true
        spotcheckInitializationStarted = false
        latestInitParams = nil
        // Same lock as the flag so a track call can't queue in between and be wiped.
        pendingTrackScreens.removeAll()
        pendingTrackEvents.removeAll()
        deferredTrackScreensAfterNavigation.removeAll()
        navigationResetInProgress = false
    }

    /// Call with pendingTrackLock held: the retry to run (after unlocking) when the gap has passed.
    private func initRetryIfDueLocked() -> (() -> Void)? {
        guard Date().timeIntervalSince(lastInitAttempt) >= Self.initRetryGap else { return nil }
        return retryInitialization
    }

    func trackScreen(_ screen: String, variables: [String: Any] = [:], customProperties: [String: Any] = [:], userDetails: [String: Any] = [:]) {
        sentry.addBreadcrumb("trackScreen", ["screen": screen])
        pendingTrackLock.lock()
        if spotcheckInitializationFailed {
            // Keep this call only when a retry starts; it runs once that init succeeds.
            let retry = initRetryIfDueLocked()
            if retry != nil {
                pendingTrackScreens.append(PendingTrackScreenRequest(
                    screen: screen,
                    variables: variables,
                    customProperties: customProperties,
                    userDetails: userDetails
                ))
            }
            pendingTrackLock.unlock()
            retry?()
            return
        }
        if !spotcheckInitializationComplete {
            pendingTrackScreens.append(PendingTrackScreenRequest(
                screen: screen,
                variables: variables,
                customProperties: customProperties,
                userDetails: userDetails
            ))
            pendingTrackLock.unlock()
            return
        }
        if navigationResetInProgress {
            deferredTrackScreensAfterNavigation.append(PendingTrackScreenRequest(
                screen: screen,
                variables: variables,
                customProperties: customProperties,
                userDetails: userDetails
            ))
            pendingTrackLock.unlock()
            return
        }
        pendingTrackLock.unlock()

        Task {
            await performTrackScreenExecute(
                screen: screen,
                variables: variables,
                customProperties: customProperties,
                userDetails: userDetails
            )
        }
    }

    private func flushPendingTrackScreens() {
        pendingTrackLock.lock()
        let batch = pendingTrackScreens
        pendingTrackScreens.removeAll()
        pendingTrackLock.unlock()
        guard !batch.isEmpty else { return }
        for request in batch {
            Task { [weak self] in
                await self?.performTrackScreenExecute(
                    screen: request.screen,
                    variables: request.variables,
                    customProperties: request.customProperties,
                    userDetails: request.userDetails
                )
            }
        }
    }

    private func flushPendingTrackEvents() {
        pendingTrackLock.lock()
        let batch = pendingTrackEvents
        pendingTrackEvents.removeAll()
        pendingTrackLock.unlock()
        for (screen, event) in batch {
            Task { [weak self] in
                await self?.executeBridge.execute("trackEvent", params: ["screen": screen, "event": event])
            }
        }
    }

    private func performTrackScreenExecute(
        screen: String,
        variables: [String: Any],
        customProperties: [String: Any],
        userDetails: [String: Any]
    ) async {
        await executeBridge.execute("trackScreen", params: [
            "screen": screen,
            "options": [
                "variables": variables,
                "customProperties": customProperties,
                "userDetails": userDetails,
            ],
        ])
    }

    func trackEvent(_ screen: String, event: [String: Any] = [:]) {
        sentry.addBreadcrumb("trackEvent", ["screen": screen, "event": event.keys.joined(separator: ",")])
        pendingTrackLock.lock()
        if spotcheckInitializationFailed {
            // Keep this call only when a retry starts; it runs once that init succeeds.
            let retry = initRetryIfDueLocked()
            if retry != nil { pendingTrackEvents.append((screen, event)) }
            pendingTrackLock.unlock()
            retry?()
            return
        }
        if !spotcheckInitializationComplete {
            pendingTrackEvents.append((screen, event))
            pendingTrackLock.unlock()
            return
        }
        pendingTrackLock.unlock()

        Task {
            await executeBridge.execute("trackEvent", params: [
                "screen": screen,
                "event": event,
            ])
        }
    }

    func handleNavigationChange() {
        pendingTrackLock.lock()
        navigationResetInProgress = true
        pendingTrackLock.unlock()

        Task { [weak self] in
            guard let self else { return }
            await self.executeBridge.executeWithNativePrelude(
                nativePrelude: {},
                functionName: "handleNavigationChange"
            )
            await MainActor.run {
                self.finishNavigationResetAndFlushDeferredTrackScreens()
            }
        }
    }

    // Swipe-back started: defer trackScreen calls until it completes or is cancelled.
    func beginInteractiveNavigation() {
        pendingTrackLock.lock()
        navigationResetInProgress = true
        pendingTrackLock.unlock()
    }

    // Swipe-back cancelled: no reset; drop the revealed screen's calls (it never became visible).
    func cancelInteractiveNavigation() {
        pendingTrackLock.lock()
        navigationResetInProgress = false
        deferredTrackScreensAfterNavigation.removeAll()
        pendingTrackLock.unlock()
    }

    private func finishNavigationResetAndFlushDeferredTrackScreens() {
        pendingTrackLock.lock()
        navigationResetInProgress = false
        let batch = deferredTrackScreensAfterNavigation
        deferredTrackScreensAfterNavigation.removeAll()
        pendingTrackLock.unlock()
        for request in batch {
            Task { [weak self] in
                await self?.performTrackScreenExecute(
                    screen: request.screen,
                    variables: request.variables,
                    customProperties: request.customProperties,
                    userDetails: request.userDetails
                )
            }
        }
    }

    // Runner for schema `$execute` actions (one instance, so SwiftUI sees a stable value); unknown names do nothing.
    private(set) lazy var genericActionRunner: (String, [String: Any]) -> Void = { [weak self] fn, params in
        guard let self, !fn.isEmpty, self.functionStore.resolve(fn) != nil else { return }
        Task { await self.executeBridge.execute(fn, params: params) }
    }

    // X tap: keeps a button spotcheck's button (legacy end()).
    func handleCloseButtonTap() {
        Task { [weak self] in
            guard let self else { return }
            await self.executeBridge.executeWithNativePrelude(
                nativePrelude: {},
                functionName: "closeButton.handleCloseButton"
            )
        }
    }

    // Public CloseSpotchecks(): full close, like navigation.
    func closeSpotCheck() {
        Task { [weak self] in
            guard let self else { return }
            await self.executeBridge.executeWithNativePrelude(
                nativePrelude: {},
                functionName: "handleNavigationChange",
                params: ["reason": "close"]
            )
        }
    }

    // MARK: - WebView Management

    func registerWebView(_ webView: WKWebView, for urlString: String) {
        if urlString.contains("classic") {
            classicWebView = webView
        } else {
            chatWebView = webView
        }
    }

    func unregisterWebView(_ webView: WKWebView) {
        if classicWebView === webView { classicWebView = nil }
        if chatWebView === webView { chatWebView = nil }
    }

    func poolClassicWebViewForSwiftUIReuse(_ webView: WKWebView) {
        pooledClassicWebView = webView
    }

    func poolChatWebViewForSwiftUIReuse(_ webView: WKWebView) {
        pooledChatWebView = webView
    }

    func dequeuePooledClassicWebView() -> WKWebView? {
        guard let w = pooledClassicWebView else { return nil }
        pooledClassicWebView = nil
        return w
    }

    func dequeuePooledChatWebView() -> WKWebView? {
        guard let w = pooledChatWebView else { return nil }
        pooledChatWebView = nil
        return w
    }

    /// When SwiftUI mounts a second `UIViewRepresentable` before `dismantleUIView` on the first, the pool is still empty
    /// but `classicWebView` / `chatWebView` already reference the live instance. Reuse that view (reparent + rewire) instead of allocating another `WKWebView`.
    func webViewForLiveReparentIfAvailable(kind: String) -> WKWebView? {
        switch kind {
        case "classic":
            return classicWebView
        case "chat":
            return chatWebView
        default:
            return nil
        }
    }

    func runWebViewInjectionPipeline() async {
        await executeBridge.execute("webviewComponent.handleWebViewInjection")
    }

    func handleWebViewMessageFromNativeBridge(rawData: String) async {
        await executeBridge.execute("webviewComponent.handleWebViewMessage", params: [
            "event": ["nativeEvent": ["data": rawData]],
        ])
    }

    private func injectIntoWebView(target: String, script: String) {
        let webView = target == "chat" ? chatWebView : classicWebView
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - State Observers

    private func setupStateObservers() {
        spotcheckStore.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.refreshStyles()
            }
            .store(in: &cancellables)

        // Rotation: recompute styles with the new screen size.
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStyles() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
    // Only the latest refresh may apply (older results can finish later).
    private var styleRefreshSeq = 0

    private func refreshStyles() {
        guard functionStore.isLoaded else { return }
        styleRefreshSeq += 1
        let seq = styleRefreshSeq

        let screenHeight = UIScreen.main.bounds.height
        let screenWidth = UIScreen.main.bounds.width

        Task {
            let next = await withTaskGroup(of: (String, [String: Any]?).self) { group in
                group.addTask {
                    let res = await self.executeBridge.execute("wrapper.getWrapperStyles", params: [
                        "screenHeight": screenHeight,
                        "screenWidth": screenWidth,
                    ]) as? [String: Any]
                    return ("wrapper", res)
                }
                group.addTask {
                    let res = await self.executeBridge.execute("closeButton.getCloseButtonStyles") as? [String: Any]
                    return ("close", res)
                }
                group.addTask {
                    let res = await self.executeBridge.execute("spotCheckButton.getSpotCheckButtonStyles") as? [String: Any]
                    return ("button", res)
                }

                var nextWrapper = self.wrapperStyles
                var nextClose = self.closeButtonStyles
                var nextButton = self.spotCheckButtonStyles

                for await (key, styles) in group {
                    guard let styles = styles else { continue }
                    if key == "wrapper" { nextWrapper = styles }
                    else if key == "close" { nextClose = styles }
                    else if key == "button" { nextButton = styles }
                }
                return (nextWrapper, nextClose, nextButton)
            }

            await MainActor.run {
                guard seq == self.styleRefreshSeq else { return }
                self.wrapperStyles = next.0
                self.closeButtonStyles = next.1
                self.spotCheckButtonStyles = next.2
            }
        }
    }
}
