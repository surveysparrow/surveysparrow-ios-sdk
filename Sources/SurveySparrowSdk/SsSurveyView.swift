//
//  SsSurveyView.swift
//  SurveySparrowSdk
//
//  Created by Gokulkrishna raju on 09/02/24.
//  Copyright © 2020 SurveySparrow. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import WebKit

@available(iOS 13.0, *)
@IBDesignable public class SsSurveyView: UIView, WKScriptMessageHandler, WKNavigationDelegate {
    
    // MARK: Properties
    private var ssWebView: WKWebView = WKWebView()
    private let surveyResponseHandler = WKUserContentController()
    private let loader: UIActivityIndicatorView = UIActivityIndicatorView()
    private var surveyLoaded: String = "surveyLoadStarted"
    private var surveyCompleted: String = "surveyCompleted"
    private static var _widgetContactId: Int64?
    
    public static var widgetContactId: Int64? {
        get {
            return _widgetContactId
        }
        set {
            _widgetContactId = newValue
        }
    }
    public var params: [String: String] = [:]
    public var surveyType: SurveySparrow.SurveyType = .CLASSIC
    public var getSurveyLoadedResponse: Bool = false
    
    @IBInspectable public var domain: String?
    @IBInspectable public var token: String?
    
    public var surveyDelegate: SsSurveyDelegate!
    
    var properties: [String: Any]?
    
    // MARK: Initialization
    public init(properties: [String: Any]) {
        super.init(frame: .zero)
        self.properties = properties
        addFeedbackView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addFeedbackView()
    }
    var closeButton = UIButton(type: .system)
    // MARK: Private methods
    private func addFeedbackView() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.userContentController = surveyResponseHandler
        ssWebView = WKWebView(frame: bounds, configuration: config)
        surveyResponseHandler.add(self, name: "surveyResponse")
        ssWebView.navigationDelegate = self
        ssWebView.backgroundColor = .gray
        ssWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(ssWebView)
        
        if let isCloseButtonEnabled = properties?["isCloseButtonEnabled"] as? Bool,
           isCloseButtonEnabled {
            
            let closeButtonWrapper = UIView()
            ssWebView.addSubview(closeButtonWrapper)
            
            closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            closeButton.tintColor = .black
            closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
            
            closeButtonWrapper.addSubview(closeButton)
            closeButtonWrapper.translatesAutoresizingMaskIntoConstraints = false
            closeButtonWrapper.backgroundColor = .white
            closeButtonWrapper.layer.cornerRadius = 4
            closeButtonWrapper.clipsToBounds = true
            
            NSLayoutConstraint.activate([
                
                closeButtonWrapper.topAnchor.constraint(equalTo: ssWebView.topAnchor, constant: 16),
                closeButtonWrapper.trailingAnchor.constraint(equalTo: ssWebView.trailingAnchor, constant: -16),
                closeButtonWrapper.widthAnchor.constraint(equalToConstant: 35),
                closeButtonWrapper.heightAnchor.constraint(equalToConstant: 35),
                
                closeButton.centerXAnchor.constraint(equalTo: closeButtonWrapper.centerXAnchor),
                closeButton.centerYAnchor.constraint(equalTo: closeButtonWrapper.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 14),
                closeButton.heightAnchor.constraint(equalToConstant: 14)
            ])
        }
        ssWebView.addSubview(loader)
        ssWebView.navigationDelegate = self
        loader.translatesAutoresizingMaskIntoConstraints = false
        loader.centerXAnchor.constraint(equalTo: ssWebView.centerXAnchor).isActive = true
        loader.centerYAnchor.constraint(equalTo: ssWebView.centerYAnchor).isActive = true
        loader.hidesWhenStopped = true
    }
    
    @objc func closeButtonTapped() {
        var isSuccess = false
        // Check if widgetContactId is valid and not 0
        if let unwrappedId = SsSurveyView.widgetContactId, unwrappedId != 0 {
            let group = DispatchGroup()
            group.enter()
            let completion: ([String: Any]) -> Void = { result in
                if let success = result["success"] as? Bool {
                    isSuccess = success
                }
            }
            closeSurvey(
                domain: domain, widgetContactId: unwrappedId, params: params, group: group,
                completion: completion)
            
            group.wait()
        }
        // Close the survey
        closeSurveyUI(isSuccess: isSuccess)
        
        if surveyDelegate != nil {
            surveyDelegate.handleCloseButtonTap()
        }
    }
    
    func closeSurveyUI(isSuccess: Bool) {
        let emptyHTML = "<html><body></body></html>"
        ssWebView.loadHTMLString(emptyHTML, baseURL: nil)
        closeButton.isHidden = true
        
        if let parentViewController = findParentViewController() {
            parentViewController.dismiss(animated: true, completion: nil)
        }
    }
    
    private func findParentViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Check if this is a navigation action caused by a hyperlink click.
        if navigationAction.navigationType == .linkActivated {
            // Handle the URL navigation here, for example:
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel) // Prevent WKWebView from loading the URL.
                return
            }
        }
        decisionHandler(.allow) // Allow other navigation actions.
    }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("Failed to load web page: \(error.localizedDescription)")
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        loader.stopAnimating()
        
        if let isCloseButtonEnabled = properties?["isCloseButtonEnabled"] as? Bool,
           isCloseButtonEnabled {
            let jsCode = """
                const styleTag = document.createElement("style");
                styleTag.innerHTML = `.ss-language-selector--wrapper { margin-right: 45px; }`;
                document.body.appendChild(styleTag);
                """
            
            webView.evaluateJavaScript(jsCode, completionHandler: { (result, error) in
                if let error = error {
                    // print(error)
                }
            })
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loader.stopAnimating()
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if surveyDelegate != nil {
            let response = message.body as! [String: AnyObject]
            let responseType = response["type"] as! String
            if(responseType == surveyLoaded){
                if surveyDelegate != nil {
                    surveyDelegate.handleSurveyLoaded(response: response)
                }
            }
            if(responseType == surveyCompleted){
                if surveyDelegate != nil {
                    surveyDelegate.handleSurveyResponse(response: response)
                }
            }
        }
    }
    
    public func loadFullscreenSurvey(parent: UIViewController,delegate:SsSurveyDelegate, domain: String? = nil, token: String? = nil, params: [String: String]? = [:] ) {
        let ssSurveyViewController = SsSurveyViewController()
        ssSurveyViewController.domain = domain
        ssSurveyViewController.token = token
        ssSurveyViewController.properties = self.properties ?? [:]
        if(params != nil){
            ssSurveyViewController.params = params ?? [:]
        }
        ssSurveyViewController.getSurveyLoadedResponse = true
        if domain != nil && token != nil {
            ssSurveyViewController.surveyDelegate = delegate
            var isActive: Bool = false
            var reason: String = ""
            let group = DispatchGroup()
            group.enter()
            let completion: ([String: Any]) -> Void = { result in
                if let active = result["active"] as? Bool {
                    isActive = active
                }
                if let reasonData = result["reason"] as? String {
                    reason = reasonData
                }
                if let widgetContactIdData = result["widgetContactId"] as? Int64 {
                    SsSurveyView.widgetContactId = widgetContactIdData
                }
            }
            validateSurvey(domain:domain,token:token,params: params, group: group,completion:completion);
            group.wait()
            if  isActive == true {
                parent.present(ssSurveyViewController, animated: true)
            } else {
                ssSurveyViewController.surveyDelegate.handleSurveyValidation(response: [
                    "active": String(isActive),
                    "reason": reason,
                ] as  [String: AnyObject])
            }
        }
    }
    
    public func loadEmbedSurvey(domain: String? = nil, token: String? = nil, params: [String: String]? = [:]) {
        self.domain = domain != nil ? domain! : self.domain
        self.token = token != nil ? token! : self.token
        if self.domain != nil && self.token != nil {
            var isActive: Bool = false
            var reason: String = ""
            let group = DispatchGroup()
            group.enter()
            let completion: ([String: Any]) -> Void = { result in
                if let active = result["active"] as? Bool {
                    isActive = active
                }
                if let reasonData = result["reason"] as? String {
                    reason = reasonData
                }
                if let widgetContactIdData = result["widgetContactId"] as? Int64 {
                    SsSurveyView.widgetContactId = widgetContactIdData
                }
            }
            validateSurvey(domain:domain,token:token,params: params,group: group,completion:completion);
            group.wait()
            if  isActive == true {
                if(params != nil){
                    self.params = params ?? [:]
                }
                loadSurvey(domain:domain,token:token)
                closeButton.isHidden = false ;
            } else {
                self.handleSurveyValidation(response: [
                    "active": String(isActive),
                    "reason": reason,
                ] as  [String: AnyObject])
            }
        }
    }
    
    // MARK: Public method
    public func loadSurvey(domain: String? = nil, token: String? = nil) {
        self.domain = domain != nil ? domain! : self.domain
        self.token = token != nil ? token! : self.token
        if self.domain != nil && self.token != nil {
            loader.startAnimating()
            var urlComponent = URLComponents()
            urlComponent.scheme = "https"
            urlComponent.host = self.domain!.trimmingCharacters(in: CharacterSet.whitespaces)
            urlComponent.path = "/\(surveyType == .NPS ? "n" : "s")/ios/\(self.token!.trimmingCharacters(in: CharacterSet.whitespaces))"
            if(getSurveyLoadedResponse){
                params["isSurveyLoaded"] = "true"
            }
            urlComponent.queryItems = params.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
            urlComponent.queryItems?.append(URLQueryItem(name: "sparrowLang", value: properties?["sparrowLang"] as? String))
            if let url = urlComponent.url {
                let request = URLRequest(url: url)
                ssWebView.load(request)
            }
        } else {
            print("Error: Domain or token is nil")
        }
    }
    
    func handleSurveyValidation(response: [String : AnyObject]) {
        print(response)
    }
}

#endif
