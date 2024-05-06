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
    
    let urlString: String
    let delegate: SsSurveyDelegate
    let state: SpotcheckState
    @State private var isLoading: Bool = true

    public var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            WebViewRepresentable(urlString: urlString, delegate: delegate, state: state, isLoading: $isLoading)
        }
    }
}

@available(iOS 15.0, *)
struct WebViewRepresentable: UIViewRepresentable {
    let urlString: String
    let delegate: SsSurveyDelegate
    let state: SpotcheckState
    @Binding var isLoading: Bool
    private let surveyResponseHandler = WKUserContentController()
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
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
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if self.parent.delegate != nil {
                let response = message.body as! [String: AnyObject]
                let responseType = response["type"] as! String
                if(responseType == surveyLoaded) {
                    if self.parent.delegate != nil {
                        self.parent.delegate.handleSurveyLoaded(response: response)
                    }
                }
                if(responseType == surveyCompleted) {
                    if self.parent.delegate != nil {
                        self.parent.state.end()
                        self.parent.delegate.handleSurveyResponse(response: response)
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
    }
}
