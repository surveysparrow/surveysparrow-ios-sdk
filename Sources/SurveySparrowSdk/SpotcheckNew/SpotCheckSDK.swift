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
    @Published var pendingInjection: String?

    /// `true` after fetch + `functionStore`/`componentStore` load + `initializeSpotcheckComponent` succeeds.
    private var spotcheckInitializationComplete = false
    private var spotcheckInitializationFailed = false
    private let pendingTrackLock = NSLock()
    private var pendingTrackScreens: [PendingTrackScreenRequest] = []
    /// Set when `handleNavigationChange` runs; `trackScreen` is deferred until unmount + `handleNavigationChange` finish.
    private var navigationResetInProgress = false
    private var deferredTrackScreensAfterNavigation: [PendingTrackScreenRequest] = []

    private let unmountAppJS = """
    (function() {
        window.dispatchEvent(new MessageEvent('message', {
            data: {"type":"UNMOUNT_APP"}
        }));
    })();
    """

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
                }

                await executeBridge.execute("initializeSpotcheckComponent", params: [
                    "domainName": domainName,
                    "targetToken": targetToken,
                    "userDetails": userDetails,
                    "variables": variables,
                    "customProperties": customProperties,
                ])

                await MainActor.run {
                    self.spotcheckInitializationComplete = true
                }
                flushPendingTrackScreens()
            } catch {
                sentry.captureP0Error(error, "SPOTCHECK_INITIALIZATION", ["action": "initialize"])
                await MainActor.run {
                    self.spotcheckInitializationFailed = true
                }
                clearPendingTrackScreensAfterInitFailure()
            }
        }
    }

    func trackScreen(_ screen: String, variables: [String: Any] = [:], customProperties: [String: Any] = [:], userDetails: [String: Any] = [:]) {
        pendingTrackLock.lock()
        if spotcheckInitializationFailed {
            pendingTrackLock.unlock()
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

    private func clearPendingTrackScreensAfterInitFailure() {
        pendingTrackLock.lock()
        pendingTrackScreens.removeAll()
        deferredTrackScreensAfterNavigation.removeAll()
        navigationResetInProgress = false
        pendingTrackLock.unlock()
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
        await Task.yield()
        await MainActor.run { }
    }

    func trackEvent(_ screen: String, event: [String: Any] = [:]) {
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
                nativePrelude: { await self.injectUnmountApp() },
                functionName: "handleNavigationChange"
            )
            await MainActor.run {
                self.finishNavigationResetAndFlushDeferredTrackScreens()
            }
        }
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

    func closeSpotCheck() {
        Task { [weak self] in
            guard let self else { return }
            await self.executeBridge.executeWithNativePrelude(
                nativePrelude: { await self.injectUnmountApp() },
                functionName: "closeButton.handleCloseButton"
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

    /// `handleWebViewInjection.js` flips `isMounted` only after `classicWebViewRef` / `chatWebViewRef` inject; those refs are absent on iOS, which uses `WKWebView.evaluateJavaScript` instead — mirror fullscreen parity here after a successful native inject.
    func dispatchFullscreenIsMountedAfterNativeInjection(error: Error?) {
        guard error == nil else { return }
        let spotCheckState = spotcheckStore.getState()["SpotCheckState"] as? [String: Any] ?? [:]
        let spotCheckDetails = spotCheckState["spotCheckDetails"] as? [String: Any] ?? [:]
        guard spotCheckDetails["isFullScreenMode"] as? Bool == true else { return }
        spotcheckStore.dispatch([
            "spotCheckDetails": [
                "isMounted": true,
            ],
        ])
    }

    func runWebViewInjectionPipeline() async {
        await executeBridge.execute("webviewComponent.handleWebViewInjection")
        // dispatchWrapper from JS schedules MainActor work asynchronously — yield so merged state is visible.
        await Task.yield()
        await MainActor.run { }

        let storeState = spotcheckStore.getState()
        let spotCheckState = storeState["SpotCheckState"] as? [String: Any] ?? [:]
        let webViewDetails = spotCheckState["webViewDetails"] as? [String: Any] ?? [:]

        let isClassicLoading = webViewDetails["isClassicLoading"] as? Bool ?? true
        let isChatLoading = webViewDetails["isChatLoading"] as? Bool ?? true
        let isCurrentSpotcheckChat = webViewDetails["isCurrentSpotcheckChat"] as? Bool
        let injectionData = webViewDetails["webViewInjectionData"] as? String ?? ""
        if injectionData.isEmpty {
            return
        }

        await MainActor.run {
            if isCurrentSpotcheckChat == false && !isClassicLoading {
                if let wv = self.classicWebView {
                    wv.evaluateJavaScript(injectionData) { [weak self] _, err in
                        self?.dispatchFullscreenIsMountedAfterNativeInjection(error: err)
                    }
                } else {
                    self.pendingInjection = injectionData
                }
            } else if isCurrentSpotcheckChat == true && !isChatLoading {
                if let wv = self.chatWebView {
                    wv.evaluateJavaScript(injectionData) { [weak self] _, err in
                        self?.dispatchFullscreenIsMountedAfterNativeInjection(error: err)
                    }
                } else {
                    self.pendingInjection = injectionData
                }
            } else if isClassicLoading || isChatLoading {
                self.pendingInjection = injectionData
            }
        }
    }

    /// Mirrors backend `handleWebViewMessage` paths that call `injectUnmountApp` (refs are no-op on iOS; native WKWebView inject here).
    func handleWebViewMessageFromNativeBridge(rawData: String) async {
        let params: [String: Any] = [
            "event": ["nativeEvent": ["data": rawData]],
        ]

        if rawData == "captureImage" {
            await executeBridge.execute("webviewComponent.handleWebViewMessage", params: params)
            return
        }

        guard let jsonData = rawData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let messageType = json["type"] as? String
        else {
            await executeBridge.execute("webviewComponent.handleWebViewMessage", params: params)
            return
        }

        let storeState = spotcheckStore.getState()
        let spotCheckState = storeState["SpotCheckState"] as? [String: Any] ?? [:]
        let spotCheckDetails = spotCheckState["spotCheckDetails"] as? [String: Any] ?? [:]

        if messageType == "surveyCompleted" {
            // Run backend first (listener → keyboard → bundled injectUnmountApp noop without refs → dispatch).
            // Then native WKWebView unmount; refs-based inject is no-op on iOS (see webviewHelpers.js).
            await executeBridge.execute("webviewComponent.handleWebViewMessage", params: params)
            await injectUnmountApp()
            return
        }

        if messageType == "thankYouPageSubmission" {
            let mode = spotCheckDetails["mode"] as? String ?? ""
            let closeButton = spotCheckDetails["closeButton"] as? [String: Any]
            let closeEnabled = closeButton?["isEnabled"] as? Bool ?? false
            let delayedMiniCardUnmount = (mode == "miniCard" && !closeEnabled)

            await executeBridge.execute("webviewComponent.handleWebViewMessage", params: params)

            if delayedMiniCardUnmount {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await injectUnmountApp()
            }
            return
        }
        

        await executeBridge.execute("webviewComponent.handleWebViewMessage", params: params)
    }

    func injectUnmountApp() async {
        let storeState = spotcheckStore.getState()
        let spotCheckState = storeState["SpotCheckState"] as? [String: Any] ?? [:]
        let webViewDetails = spotCheckState["webViewDetails"] as? [String: Any] ?? [:]
        let isCurrentSpotcheckChat = webViewDetails["isCurrentSpotcheckChat"] as? Bool ?? false

        await MainActor.run {
            if isCurrentSpotcheckChat {
                self.chatWebView?.evaluateJavaScript(self.unmountAppJS)
            } else {
                self.classicWebView?.evaluateJavaScript(self.unmountAppJS)
            }
        }
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
    }

    private var cancellables = Set<AnyCancellable>()

    private func refreshStyles() {
        guard functionStore.isLoaded else { return }

        let screenHeight = UIScreen.main.bounds.height
        let screenWidth = UIScreen.main.bounds.width

        Task {
            await withTaskGroup(of: (String, [String: Any]?).self) { group in
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

                await MainActor.run {
                    self.wrapperStyles = nextWrapper
                    self.closeButtonStyles = nextClose
                    self.spotCheckButtonStyles = nextButton
                }
            }
        }
    }
}
