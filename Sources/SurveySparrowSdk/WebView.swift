//
//  File.swift
//  
//
//  Created by Gokulkrishna raju on 03/04/24.
//

import SwiftUI
import WebKit

@available(iOS 15.0, *)
public struct WebView: View {
    
    let delegate: SsSpotcheckDelegate
    let state: SpotcheckState
    @State private var isLoading: Bool = true

    public var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            WebViewRepresentable(urlString: state.spotcheckURL, delegate: delegate, state: state, isLoading: $isLoading)
        }
    }
}

@available(iOS 13.0, *)
struct WebViewRepresentable: UIViewRepresentable {
    let urlString: String
    let delegate: SsSpotcheckDelegate
    let state: SpotcheckState
    @Binding var isLoading: Bool
    private let surveyResponseHandler = WKUserContentController()
    
    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        URLCache.shared.removeAllCachedResponses()
        let htmlString = "<html><body></body></html>"
        uiView.loadHTMLString(htmlString, baseURL: nil)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.userContentController = surveyResponseHandler
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        surveyResponseHandler.add(context.coordinator, name: "surveyResponse")
        surveyResponseHandler.add(context.coordinator, name: "spotCheckData")
        surveyResponseHandler.add(context.coordinator, name: "flutterSpotCheckData")
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        
        private var surveyLoaded: String = "surveyLoadStarted"
        private var surveyCompleted: String = "surveyCompleted"
        private var spotCheckData: String = "spotCheckData"
        private var closeModel: String = "closeModal"
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if self.parent.delegate != nil {
                var response: [String: AnyObject] = [:]

                                if let bodyString = message.body as? String,
                                   let bodyData = bodyString.data(using: .utf8),
                                   let parsed = try? JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: AnyObject] {
                                    response = parsed
                                } else if let bodyDict = message.body as? [String: AnyObject] {
                                    response = bodyDict
                                } else {
                                    print("Unable to parse message.body")
                                    return
                                }
                let responseType = response["type"] as! String
                if responseType == surveyLoaded {
                    if self.parent.delegate != nil {
                        Task{
                            await self.parent.delegate.handleSurveyLoaded(response: response)
                        }
                    }
                } else if responseType == surveyCompleted {
                    if self.parent.delegate != nil {
                        self.parent.state.end()
                        Task{
                            await self.parent.delegate.handleSurveyResponse(response: response)
                        }
                    
                    }
                }
                else if responseType == spotCheckData {
                    if self.parent.delegate != nil {
                        if let currentQuestionSize = response["data"]?["currentQuestionSize"] as? [String: Any],
                           let height = currentQuestionSize["height"] as? Double {
                            self.parent.state.currentQuestionHeight = height
                        }
                    }
                    
                    if let isCloseButtonEnabled = response["data"]?["isCloseButtonEnabled"] as? Bool{
                                                self.parent.state.isCloseButtonEnabled = isCloseButtonEnabled
                        
                        if self.parent.delegate != nil {
                          
                            Task {
                                await self.parent.delegate.handleSurveyResponse(response: [
                                    "type": "surveySubmitted",
                                    "data": "{}"
                                ] as [String: AnyObject])

                            }
                           
                        }
                        
                        
                                            }
                }
            }

        }
        
        var parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
        
        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
        
        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error){
            print("Failed to load web page: \(error.localizedDescription)")
        }
    }
}
