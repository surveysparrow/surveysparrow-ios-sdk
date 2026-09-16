import SwiftUI

// MARK: - Root View — Composes Wrapper + SpotCheckButton

@available(iOS 15.0, *)
struct SpotCheckRootView: View {
    @ObservedObject var sdk: SpotCheckSDK

    var body: some View {
        let storeState = sdk.spotcheckStore.state
        let spotCheckState = storeState["SpotCheckState"] as? [String: Any] ?? [:]

        ZStack {
            WrapperView(sdk: sdk)
            SpotCheckButtonView(sdk: sdk)
        }
        .environmentObject(sdk)
        .allowsHitTesting(isInteractive(spotCheckState))
    }

    private func isInteractive(_ state: [String: Any]) -> Bool {
        let details = state["spotCheckDetails"] as? [String: Any] ?? [:]
        let isVisible = details["isVisible"] as? Bool ?? false
        let isButton = details["isSpotCheckButton"] as? Bool ?? false
        return isVisible || isButton
    }
}

// MARK: - Stable WebView slot (critical for WKWebView lifecycle)

/// Holds **one** `AnyView(WebViewArea…)` for the wrapper `children` slot. Building a fresh `AnyView(...)`
/// on every `WrapperView.body` tick makes SwiftUI treat the slot as a new subtree → `WebViewArea`/`WKWebView`
/// dismantle + rebuild on large state updates (e.g. RESET_STATE after `handleSpotCheckButtonPress`).
@available(iOS 15.0, *)
final class WebViewSlotHolder: ObservableObject {
    let childrenSlot: AnyView
    init(sdk: SpotCheckSDK) {
        childrenSlot = AnyView(WebViewArea(sdk: sdk).id("spotcheck-webview-slot"))
    }
}

// MARK: - Wrapper View

@available(iOS 15.0, *)
struct WrapperView: View {
    @ObservedObject var sdk: SpotCheckSDK
    @StateObject private var webViewSlotHolder: WebViewSlotHolder

    init(sdk: SpotCheckSDK) {
        self.sdk = sdk
        _webViewSlotHolder = StateObject(wrappedValue: WebViewSlotHolder(sdk: sdk))
    }

    var body: some View {
        let storeState = sdk.spotcheckStore.state
        let spotCheckState = storeState["SpotCheckState"] as? [String: Any] ?? [:]

        if sdk.componentStore.isLoaded, let wrapperSchema = sdk.componentStore.getSchema(for: "wrapper") {
            let context = BuilderContext(
                state: spotCheckState,
                styles: sdk.wrapperStyles,
                slots: [
                    "children": webViewSlotHolder.childrenSlot,
                ],
                handlers: [
                    "handleExitAnimationComplete": { [weak sdk] in
                        Task { await sdk?.executeBridge.execute("handleExitAnimationComplete") }
                    } as () -> Void,
                ]
            )
            Builder(schema: wrapperSchema, context: context)
                .environmentObject(sdk)
        }
    }
}

// MARK: - WebView Area

@available(iOS 15.0, *)
struct WebViewArea: View {
    @ObservedObject var sdk: SpotCheckSDK

    var body: some View {
        let storeState = sdk.spotcheckStore.state
        let spotCheckState = storeState["SpotCheckState"] as? [String: Any] ?? [:]
        let injectionPipelineKey = makeInjectionPipelineKey(spotCheckState)

        if sdk.componentStore.isLoaded, let webviewSchema = sdk.componentStore.getSchema(for: "webviewComponent") {
            let context = BuilderContext(
                state: spotCheckState,
                styles: [:],
                handlers: [
                    "handleOnMessage": { } as () -> Void,
                    "handleOnError": { } as () -> Void,
                ]
            )
            Builder(schema: webviewSchema, context: context)
                .environmentObject(sdk)
                .task(id: injectionPipelineKey) {
                    guard sdk.functionStore.isLoaded else { return }
                    await sdk.runWebViewInjectionPipeline()
                }
        }
    }

    /// Same inputs as Android `LaunchedEffect(isChatLoading, isClassicLoading, webViewInjectionData)` — drives backend injection + pending stash.
    /// Uses count + fingerprint (not raw JS) so logs and SwiftUI identity stay small when `webViewInjectionData` is huge.
    private func makeInjectionPipelineKey(_ spotCheckState: [String: Any]) -> String {
        let webViewDetails = spotCheckState["webViewDetails"] as? [String: Any] ?? [:]
        let isChatLoading = webViewDetails["isChatLoading"] as? Bool ?? true
        let isClassicLoading = webViewDetails["isClassicLoading"] as? Bool ?? true
        let injectionData = webViewDetails["webViewInjectionData"] as? String ?? ""
        var hasher = Hasher()
        hasher.combine(injectionData)
        let injFingerprint = hasher.finalize()
        return "\(isChatLoading)_\(isClassicLoading)_\(injectionData.count)_\(injFingerprint)"
    }

}

// MARK: - SpotCheck Button View

@available(iOS 15.0, *)
struct SpotCheckButtonView: View {
    @ObservedObject var sdk: SpotCheckSDK

    var body: some View {
        let storeState = sdk.spotcheckStore.state
        let spotCheckState = storeState["SpotCheckState"] as? [String: Any] ?? [:]
        let details = spotCheckState["spotCheckDetails"] as? [String: Any] ?? [:]
        let isButton = details["isSpotCheckButton"] as? Bool ?? false

        if isButton, sdk.componentStore.isLoaded, let buttonSchema = sdk.componentStore.getSchema(for: "spotCheckButton") {
            let context = BuilderContext(
                state: spotCheckState,
                styles: sdk.spotCheckButtonStyles,
                handlers: [
                    "handleSpotCheckButtonPress": { [weak sdk] in
                        Task { await sdk?.executeBridge.execute("spotCheckButton.handleSpotCheckButtonPress") }
                    } as () -> Void,
                    "handleSideTabLayout": { [weak sdk] (event: [String: Any]) in
                        Task {
                            await sdk?.executeBridge.execute("spotCheckButton.handleSideTabLayout", params: [
                                "event": event,
                            ])
                        }
                    } as ([String: Any]) -> Void,
                    "handleExitAnimationComplete": { [weak sdk] in
                        Task { await sdk?.executeBridge.execute("handleExitAnimationComplete") }
                    } as () -> Void,
                ]
            )
            Builder(schema: buttonSchema, context: context)
                .environmentObject(sdk)
        }
    }
}
