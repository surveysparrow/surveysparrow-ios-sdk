import SwiftUI
import WebKit

@available(iOS 15.0, *)
struct CloseButtonComponent: View {
    let context: BuilderContext

    @EnvironmentObject private var sdk: SpotCheckSDK

    var body: some View {
        let componentState = sdk.componentStore
        guard let closeSchema = componentState.getSchema(for: "closeButton") else {
            return AnyView(EmptyView())
        }

        let closeContext = BuilderContext(
            state: context.state,
            styles: sdk.closeButtonStyles,
            handlers: [
                "handleClosePress": { [weak sdk] in
                    sdk?.closeSpotCheck()
                } as () -> Void,
            ]
        )

        return AnyView(Builder(schema: closeSchema, context: closeContext))
    }
}

// MARK: - WebView Renderer Component

@available(iOS 15.0, *)
struct WebViewRendererComponent: View {
    let props: [String: Any]
    let meta: [String: Any]
    let context: BuilderContext
    /// Stable key from `Builder` (`renderNode` path) — if this changes, SwiftUI may rebuild WKWebView.
    let builderKey: String

    @EnvironmentObject private var sdk: SpotCheckSDK

    private var uri: String {
        (props["uri"] as? String) ?? ""
    }

    /// When Redux briefly clears `classicUrl`/`chatUrl` during merges, avoid swapping WebView ↔ EmptyView.
    @State private var pinnedUri: String = ""

    private var resolvedUri: String {
        if !uri.isEmpty { return uri }
        return pinnedUri
    }

    private var webViewKind: String {
        (meta["webViewType"] as? String) ?? "?"
    }

    var body: some View {
        webContent
            .onAppear {
                if !uri.isEmpty { pinnedUri = uri }
            }
            .onChange(of: uri) { newUri in
                if !newUri.isEmpty { pinnedUri = newUri }
            }
    }

    @ViewBuilder
    private var webContent: some View {
        if resolvedUri.isEmpty {
            EmptyView()
        } else {
            SpotCheckWebView(
                urlString: resolvedUri,
                builderKey: builderKey,
                webViewKind: webViewKind,
                sdk: sdk,
                onMessage: { data in
                    Task {
                        await sdk.handleWebViewMessageFromNativeBridge(rawData: data)
                    }
                },
                onError: { errorMsg in
                    Task {
                        await sdk.executeBridge.execute("webviewComponent.handleWebViewError", params: [
                            "error": errorMsg,
                        ])
                    }
                }
            )
            .id("spotcheck-wk-\(webViewKind)")
        }
    }
}

// MARK: - SpotCheck Button Component

@available(iOS 15.0, *)
struct SpotCheckButtonComponent: View {
    let context: BuilderContext

    @EnvironmentObject private var sdk: SpotCheckSDK

    var body: some View {
        let componentState = sdk.componentStore
        guard let buttonSchema = componentState.getSchema(for: "spotCheckButton") else {
            return AnyView(EmptyView())
        }

        let buttonContext = BuilderContext(
            state: context.state,
            styles: sdk.spotCheckButtonStyles,
            handlers: [
                "handleSpotCheckButtonPress": { [weak sdk] in
                    Task { await sdk?.executeBridge.execute("spotCheckButton.handleSpotCheckButtonPress") }
                } as Any,
                "handleSideTabLayout": { [weak sdk] (event: [String: Any]) in
                    Task {
                        await sdk?.executeBridge.execute("spotCheckButton.handleSideTabLayout", params: [
                            "event": event,
                        ])
                    }
                } as Any,
            ]
        )

        return AnyView(Builder(schema: buttonSchema, context: buttonContext))
    }
}

// MARK: - SpotCheck WebView (WKWebView)

@available(iOS 15.0, *)
struct SpotCheckWebView: UIViewRepresentable {
    let urlString: String
    let builderKey: String
    let webViewKind: String
    let sdk: SpotCheckSDK
    let onMessage: (String) -> Void
    let onError: (String) -> Void

    private static let scriptMessageNames = ["surveyResponse", "spotCheckData", "flutterSpotCheckData"]

    func makeUIView(context: Context) -> WKWebView {
        if webViewKind == "classic", let pooled = sdk.dequeuePooledClassicWebView() {
            return attachPooledWebView(pooled, context: context)
        }
        if webViewKind == "chat", let pooled = sdk.dequeuePooledChatWebView() {
            return attachPooledWebView(pooled, context: context)
        }
        // Pool empty but SwiftUI already created a host — registered ref is still the live WKWebView (second makeUIView before first dismantle).
        if let live = sdk.webViewForLiveReparentIfAvailable(kind: webViewKind) {
            return attachPooledWebView(live, context: context)
        }
        return createNewWebView(context: context)
    }

    /// Rebind script handlers + navigation to the new `Coordinator` after SwiftUI pooled or reparented this `WKWebView`.
    private func attachPooledWebView(_ webView: WKWebView, context: Context) -> WKWebView {
        Self.rewireScriptHandlers(webView: webView, coordinator: context.coordinator)
        webView.navigationDelegate = context.coordinator

        context.coordinator.sdk = sdk
        context.coordinator.lastBuilderKey = builderKey
        context.coordinator.lastWebViewKind = webViewKind
        context.coordinator.lastUrlString = urlString

        if let url = URL(string: urlString) {
            let current = webView.url?.absoluteString ?? ""
            if current != url.absoluteString {
                webView.load(URLRequest(url: url))
            }
        }

        sdk.registerWebView(webView, for: urlString)
        return webView
    }

    private static func rewireScriptHandlers(webView: WKWebView, coordinator: Coordinator) {
        let cc = webView.configuration.userContentController
        for name in scriptMessageNames {
            cc.removeScriptMessageHandler(forName: name)
            cc.add(coordinator, name: name)
        }
    }

    private func createNewWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let contentController = WKUserContentController()

        let defaultJS = """
        window.addEventListener('scroll', function() {
            if (document.querySelector('.surveysparrow-chat__wrapper')) {
                window.scrollTo(0, 0);
            }
        }, { passive: false });

        (function() {
            var styleTag = document.createElement("style");
            styleTag.innerHTML = ".surveysparrow-chat__wrapper .ss-language-selector--wrapper { margin-right: 45px; } .close-btn-chat--spotchecks { display: none !important; }";
            document.head.appendChild(styleTag);
        })();

        window.flutterSpotCheckData = {
            postMessage: function(data) {
                window.webkit.messageHandlers.spotCheckData.postMessage(data);
            }
        };
        """
        let userScript = WKUserScript(source: defaultJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(userScript)

        contentController.add(context.coordinator, name: "surveyResponse")
        contentController.add(context.coordinator, name: "spotCheckData")
        contentController.add(context.coordinator, name: "flutterSpotCheckData")

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.bounces = false
        // SwiftUI applies safe-area padding on the overlay root; avoid double insets inside WKWebView.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.sdk = sdk
        context.coordinator.lastBuilderKey = builderKey
        context.coordinator.lastWebViewKind = webViewKind
        context.coordinator.lastUrlString = urlString

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        sdk.registerWebView(webView, for: urlString)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.lastBuilderKey = builderKey
        context.coordinator.lastWebViewKind = webViewKind

        if context.coordinator.lastUrlString != urlString {
            context.coordinator.lastUrlString = urlString
            if let url = URL(string: urlString) {
                uiView.load(URLRequest(url: url))
                sdk.registerWebView(uiView, for: urlString)
            }
        }

        // Legacy pattern: only the active classic/chat WebView applies `pendingInjection` when loading flags allow (avoids wrong WKWebView clearing pending).
        if let injectionJS = sdk.pendingInjection, !injectionJS.isEmpty {
            let storeState = sdk.spotcheckStore.state
            let spotCheckState = storeState["SpotCheckState"] as? [String: Any] ?? [:]
            let wd = spotCheckState["webViewDetails"] as? [String: Any] ?? [:]
            let isClassicLoading = wd["isClassicLoading"] as? Bool ?? true
            let isChatLoading = wd["isChatLoading"] as? Bool ?? true
            let isCurrentSpotcheckChat = wd["isCurrentSpotcheckChat"] as? Bool

            let isThisClassic = webViewKind == "classic"
            let isThisChat = webViewKind == "chat"
            let classicReady = isThisClassic && isCurrentSpotcheckChat != true && !isClassicLoading
            let chatReady = isThisChat && isCurrentSpotcheckChat == true && !isChatLoading

            if classicReady || chatReady {
                uiView.evaluateJavaScript(injectionJS) { _, err in
                    // Avoid @Published updates during UIViewRepresentable.updateUIView (SwiftUI warning).
                    DispatchQueue.main.async { [weak sdk] in
                        guard let sdk else { return }
                        sdk.dispatchFullscreenIsMountedAfterNativeInjection(error: err)
                        sdk.pendingInjection = nil
                    }
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        guard let sdk = coordinator.sdk else { return }
        switch coordinator.lastWebViewKind {
        case "classic":
            sdk.poolClassicWebViewForSwiftUIReuse(uiView)
        case "chat":
            sdk.poolChatWebViewForSwiftUIReuse(uiView)
        default:
            sdk.unregisterWebView(uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage, onError: onError)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var sdk: SpotCheckSDK?
        let onMessage: (String) -> Void
        let onError: (String) -> Void

        var lastBuilderKey: String = ""
        var lastWebViewKind: String = ""
        var lastUrlString: String = ""

        init(onMessage: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onMessage = onMessage
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let bodyString = message.body as? String {
                onMessage(bodyString)
            } else if let bodyDict = message.body as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: bodyDict),
                      let str = String(data: data, encoding: .utf8) {
                onMessage(str)
            } else {
                // Unsupported script message body type; ignore.
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let sdk = sdk else { return }
            Task {
                await sdk.runWebViewInjectionPipeline()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError(error.localizedDescription)
        }
    }
}
