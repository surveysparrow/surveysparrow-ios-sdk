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
    @State public var urlType: String

    public var body: some View {
        ZStack {
            if  urlType == "classic" ? state.isClassicLoading : state.isChatLoading{
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            WebViewRepresentable(
                urlString: urlType == "classic" ? state.classicUrl : state.chatUrl,
                delegate: delegate,
                state: state,
                urlType: $urlType
            )
        }
    }
}

@available(iOS 13.0, *)
struct WebViewRepresentable: UIViewRepresentable {
    let urlString: String
    let delegate: SsSpotcheckDelegate
    let state: SpotcheckState
    @Binding var urlType: String
    private let surveyResponseHandler = WKUserContentController()
    
    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        URLCache.shared.removeAllCachedResponses()
        let htmlString = "<html><body></body></html>"
        uiView.loadHTMLString(htmlString, baseURL: nil)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true

        let js = """
          window.addEventListener(
            'scroll',
            function () {
              if (
                document.querySelector(
                  '.surveysparrow-chat__wrapper'
                )
              ) {
                window.scrollTo(0, 0);
              }
            },
            { passive: false }
          );

          (function() {
            var styleTag = document.createElement("style");
            styleTag.innerHTML = `
                .surveysparrow-chat__wrapper .ss-language-selector--wrapper {
                    margin-right: 45px;
                }
                .close-btn-chat--spotchecks {
                    display: none !important;
                }
            `;
            document.head.appendChild(styleTag);
        })();
        """

        let userScript = WKUserScript(
            source: js,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )


        let contentController = WKUserContentController()
        contentController.addUserScript(userScript)

        contentController.add(context.coordinator, name: "surveyResponse")
        contentController.add(context.coordinator, name: "spotCheckData")
        contentController.add(context.coordinator, name: "flutterSpotCheckData")

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        
        if(urlType=="classic"){
            DispatchQueue.main.async{
                self.state.classicWebView = webView
            }
        }
        else{
            DispatchQueue.main.async{
                self.state.chatWebView = webView
            }
          
        }
        webView.navigationDelegate = context.coordinator
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
        private var partialSubmission: String = "partialSubmission"
        private var thankYouPageSubmission: String = "thankYouPageSubmission"
        
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
                        let capturedResponse = response
                        Task {
                            await self.parent.delegate.handleSurveyLoaded(response: capturedResponse)
                        }
                        
                    }
                } else if responseType == surveyCompleted {
                    if self.parent.delegate != nil {
                        self.parent.state.end()
                        let capturedResponse = response
                        Task {
                            await self.parent.delegate.handleSurveyResponse(response: capturedResponse)
                        }
                    }
                }
                else if responseType == partialSubmission
                {
                    if self.parent.delegate != nil {
                        let capturedResponse = response
                        Task {
                            await self.parent.delegate.handlePartialSubmission(response: capturedResponse)
                        }
                    }
                }
                else if responseType == thankYouPageSubmission
                {
                    self.parent.state.isThankyouPageSubmission = true
                    if self.parent.delegate != nil {
                        let capturedResponse = response
                        Task {
                            await self.parent.delegate.handleSurveyResponse(response: capturedResponse)
                        }
                    }
                    
                    if(self.parent.state.spotChecksMode == "miniCard" && !self.parent.state.isCloseButtonEnabled)
                    {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            self.parent.state.end()
                        }
                    }
                    else{
                        self.parent.state.isCloseButtonEnabled = true
                    }
                }
                
                else if responseType == spotCheckData {
                    if self.parent.delegate != nil {
                        if let currentQuestionSize = response["data"]?["currentQuestionSize"] as? [String: Any],
                           let height = currentQuestionSize["height"] as? Double {
                            
                            self.parent.state.currentQuestionHeight = height
                            
                            if(self.parent.state.spotChecksMode=="miniCard" && self.parent.state.isCloseButtonEnabled){
                                self.parent.state.currentQuestionHeight -= 40;
                            }
                            if(self.parent.state.spotChecksMode=="miniCard" && self.parent.state.avatarEnabled){
                                self.parent.state.currentQuestionHeight -= 56;
                            }
                        }

                        if let isCloseButtonEnabled = response["data"]?["isCloseButtonEnabled"] as? Bool{
                            self.parent.state.isCloseButtonEnabled = isCloseButtonEnabled
                        }
                    }
              
                } else if responseType == "slideInFrame" {
                    self.parent.state.isMounted = true
                } else if responseType == "chatLoadEvent" {
                    self.parent.state.isChatLoading = false
                } else if responseType == "classicLoadEvent" {
                    self.parent.state.isClassicLoading = false
                }
            }


        }
        
        var parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
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
