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
                    sdk?.handleCloseButtonTap()
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

    private var canShow: Bool {
        (props["canShow"] as? Bool) ?? true
    }

    // Hidden webviews stay mounted (preloaded) but invisible and untouchable.
    var body: some View {
        webContent
            .opacity(canShow ? 1 : 0)
            .allowsHitTesting(canShow)
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

    private static var scriptProxyKey = 0

    // Point the WebView's permanent handler at the new coordinator; remove/add left a gap where page messages were lost.
    private static func rewireScriptHandlers(webView: WKWebView, coordinator: Coordinator) {
        if let proxy = objc_getAssociatedObject(webView, &scriptProxyKey) as? ScriptMessageProxy {
            proxy.target = coordinator
            return
        }
        let proxy = ScriptMessageProxy(target: coordinator)
        let cc = webView.configuration.userContentController
        for name in scriptMessageNames {
            cc.removeScriptMessageHandler(forName: name)
            cc.add(proxy, name: name)
        }
        objc_setAssociatedObject(webView, &scriptProxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func createNewWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let contentController = WKUserContentController()

        // Native bridge shim stays here; the page script can come from the backend.
        let bridgeJS = """
        window.flutterSpotCheckData = {
            postMessage: function(data) {
                window.webkit.messageHandlers.spotCheckData.postMessage(data);
            }
        };
        """
        let defaultPageJS = """
        window.addEventListener('scroll', function() {
            if (document.querySelector('.surveysparrow-chat__wrapper')) {
                window.scrollTo(0, 0);
            }
        }, { passive: false });

        (function() {
            var styleTag = document.createElement("style");
            styleTag.innerHTML = ".close-btn-chat--spotchecks { display: none !important; }";
            document.head.appendChild(styleTag);
        })();
        """
        let defaultJS = bridgeJS + "\n" + (sdk.remoteWebViewScript ?? defaultPageJS)
        let userScript = WKUserScript(source: defaultJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(userScript)

        let proxy = ScriptMessageProxy(target: context.coordinator)
        for name in Self.scriptMessageNames {
            contentController.add(proxy, name: name)
        }

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        objc_setAssociatedObject(webView, &Self.scriptProxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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

// One handler per WebView for its lifetime; forwards to the current SwiftUI coordinator.
final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
