//
//  SpotcheckState.swift
//
//
//  Created by Gokulkrishna raju on 03/04/24.
//

import SwiftUI
import CoreLocation
import WebKit

@available(iOS 13.0, *)
public class SpotcheckState: ObservableObject {
    
    @Published public var isVisible = false
    @Published public var spotcheckPosition: String = "bottom"
    @Published public var spotcheckURL: String = ""
    @Published public var spotcheckID: Int64 = 0
    @Published public var spotcheckContactID: Int64 = 0
    @Published public var afterDelay: Double = 0.0
    @Published public var maxHeight: Double = 0.5
    @Published public var currentQuestionHeight: Double = 0
    @Published public var isFullScreenMode: Bool = true
    @Published public var isBannerImageOn: Bool = false
    @Published public var triggerToken: String = ""
    @Published public var closeButtonStyle: [String: String] = [:]
    @Published public var isCloseButtonEnabled: Bool = false
    @Published public var surveyDelegate: SsSpotcheckDelegate
    @Published public var  chatUrl: String = ""
    @Published public var  spotChecksMode: String = ""
    @Published public var avatarEnabled: Bool = false
    @Published public var avatarUrl: String = ""
    @Published public var  spotCheckType: String = ""
    @Published public var  classicUrl: String = ""
    @Published public var classicWebView: WKWebView?
    @Published public var chatWebView: WKWebView?
    @Published public var isMounted: Bool = false
    @Published public var chatBool: Bool = false
    @Published public var classicBool: Bool = false
    @Published public var isSpotCheckButton: Bool = false
    @Published public var spotCheckButtonConfig: [String: Any] = [:]
    @Published public var showSurveyContent: Bool = true
    @Published public var isThankyouPageSubmission: Bool = false
    @Published public var isChat: Bool = false
    @Published public var  screenName: String = ""
    @Published public var appearance: [String: Any] = [:]
    @Published public var isChatLoading: Bool = true {
        
        didSet {
            if(!chatBool){
                chatBool = true
                chatWebView?.evaluateJavaScript(injectionJS)
                self.start()
            }
        }

      }
    @Published public var isClassicLoading: Bool = true {
        
        didSet {

            if(!classicBool){
                classicBool = true
                    self.classicWebView?.evaluateJavaScript(self.injectionJS)
                    self.start()
            }

        }

      }
    @Published private var isSpotPassed: Bool = false
    @Published private var injectionJS: String = ""
    @Published private var isChecksPassed: Bool = false
    @Published private var customEventsSpotChecks: [[String: Any]] = []
    @Published private var filteredSpotChecks: [[String: Any]] = []
    
    
    var targetToken: String
    var domainName: String
    var userDetails: [String: Any]
    var variables: [String: Any]
    var customProperties: [String: Any]
    var traceId: String = ""
    var sparrowLang: String = ""
    let defaults = UserDefaults.standard
    
    public init(targetToken:String, domainName: String, userDetails: [String: Any], variables: [String: Any], customProperties: [String: Any], sparrowLang: String, surveyDelegate: SsSpotcheckDelegate) {
        self.targetToken = targetToken
        self.domainName = domainName
        self.userDetails = userDetails
        self.variables = variables
        self.customProperties = customProperties
        self.sparrowLang = sparrowLang
        self.surveyDelegate = surveyDelegate
        if self.traceId.isEmpty {
            self.traceId = generateTraceId()
            if defaults.string(forKey: "SurveySparrowUUID") == nil {
                defaults.set("", forKey: "SurveySparrowUUID")
            }
        }
        
        DispatchQueue.main.async {
            self.initializeWidget()
        }
    }
    
    
    
    private func initializeWidget() {
        guard !targetToken.isEmpty, !domainName.isEmpty else { return }

        let urlString = "https://\(domainName)/api/internal/spotcheck/widget/\(targetToken)/init"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error initializing widget: \(error)")
                return
            }

            guard let data = data else { return }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let filtered = json["filteredSpotChecks"] as? [[String: Any]] {
                    DispatchQueue.main.async {
                        self.filteredSpotChecks = filtered
                    }
                    var classicIframe = false
                    var chatIframe = false

                    for spotcheck in filtered {
                        if let appearance = spotcheck["appearance"] as? [String: Any],
                           let mode = appearance["mode"] as? String {
                        
                            if mode == "card" || mode == "miniCard" {
                                classicIframe = true
                            } else if mode == "fullScreen" {
                                if let survey = spotcheck["survey"] as? [String: Any],
                                   let surveyType = survey["surveyType"] as? String {
                                    
                                    if self.isChatSurvey(surveyType) {
                                        chatIframe = true
                                    } else {
                                        classicIframe = true
                                    }
                                }
                            }
                        }
                    }

                    DispatchQueue.main.async {
                        self.chatUrl = chatIframe ? "https://\(self.domainName)/eui-template/chat?isSpotCheck=true" : ""
                        self.classicUrl = classicIframe ? "https://\(self.domainName)/eui-template/classic?isSpotCheck=true" : ""
                    }
                }

            } catch {
                print("Error decoding response: \(error)")
            }
        }.resume()
    }



        func getUserAgent(completion: @escaping (String) -> Void) {
        var userAgent = "Mozilla/5.0 "

        let device = UIDevice.current
        let deviceName = device.name
        let model = device.model
        let iosVersion = device.systemVersion.replacingOccurrences(of: ".", with: "_")

        let isTablet = UIDevice.current.userInterfaceIdiom == .pad

        if isTablet {
            userAgent += "(iPad; CPU iOS \(iosVersion) like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Safari/537.36"
        } else {
            userAgent += "(\(deviceName) - \(model) CPU iOS \(iosVersion) like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/537.36"
        }

        completion(userAgent)
        }


    private func isChatSurvey(_ type: String) -> Bool {
        return type == "Conversational" ||
               type == "CESChat" ||
               type == "NPSChat" ||
               type == "CSATChat"
    }
    
    public func start() {
        self.isVisible = true
    }
    
    public func end(isNavigation: Bool = false) {

            let targetWebView = spotCheckType == "chat" ? chatWebView : classicWebView
            let jsToInject = """
            (function() {
                window.dispatchEvent(new MessageEvent('message', {
                    data: {"type":"UNMOUNT_APP"}
                }));
            })();
            """

            DispatchQueue.main.async {
                targetWebView?.evaluateJavaScript(jsToInject)
            }
        
        if(!self.isSpotCheckButton || isNavigation){
            self.isFullScreenMode = false
            self.spotcheckID = 0
            self.spotcheckPosition = "bottom"
            self.currentQuestionHeight = 0.0
            self.isCloseButtonEnabled = false
            self.spotcheckContactID = 0
            self.spotcheckURL = ""
            self.isMounted = false
            self.spotChecksMode = ""
            self.avatarEnabled = false
            self.avatarUrl = ""
            self.injectionJS = ""
            self.spotCheckType = ""
            if (self.isSpotCheckButton) {
                self.showSurveyContent = true
            }
            self.isSpotCheckButton = false
            self.isThankyouPageSubmission = false
            self.isChat = false
            self.screenName = ""
            self.appearance = [:]
        }
        else if(self.isVisible){
            self.isVisible = false
            self.showSurveyContent = false
            self.isMounted = false
            self.isThankyouPageSubmission = false
            self.currentQuestionHeight = 0.0
        }
    }
    
    public func sendTrackScreenRequest(screen: String, completion: @escaping (Bool, Bool) -> Void) {
        if(
            self.userDetails["email"] == nil
            && self.userDetails["uuid"] == nil
            && self.userDetails["mobile"] == nil
        ) {
            if let uuid = defaults.string(forKey: "SurveySparrowUUID"),
               !uuid.isEmpty {
                self.userDetails["uuid"] = uuid
            }
        }
        
        let payload: [String: Any] = [
            "screenName": screen ?? "",
            "variables": self.variables,
            "customProperties": self.customProperties,
            "traceId": self.traceId,
            "userDetails": self.userDetails,
            "visitor": [
                "deviceType": "MOBILE",
                "operatingSystem": "iOS",
                "screenResolution": [
                    "width": UIScreen.main.bounds.width,
                    "height": UIScreen.main.bounds.height
                ],
                "currentDate": self.getCurrentDate(),
                "timezone": TimeZone.current.identifier
            ]
        ]
        
        guard let baseURL = URL(string: "https://\(self.domainName)/api/internal/spotcheck/widget/\(self.targetToken)/properties?isSpotCheck=true&sdk=IOS") else {
            print("Invalid URL")
            completion(false, false)
            return
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "isSpotCheck", value: "true")
        ]

        guard let url = components?.url else {
            print("Failed to create URL with query parameters")
            completion(false, false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var reqData: Data
        do {
            reqData = try JSONSerialization.data(withJSONObject: payload)
            
        } catch {
            print("Error serializing JSON: \(error)")
            completion(false, false)
            return
        }
        
        URLSession.shared.uploadTask(with: request, from: reqData) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                completion(false, false)
                return
            }
            
            guard let data = data else {
                print("No data received")
                completion(false, false)
                return
            }
            
            do {
                // Responce
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        
                if let uuid = json?["uuid"] as? String {
                    let locuuid = self.defaults.string(forKey: "SurveySparrowUUID")
                    if locuuid == nil || ((locuuid?.isEmpty) != nil) {
                        self.defaults.set(uuid, forKey: "SurveySparrowUUID")
                    }
                }
                
                DispatchQueue.main.async {
                    
                    if let show = json?["show"] as? Bool {
                        
                        if show == true {
                            
                            self.setAppearance(json: json ?? [:], screen: screen)
                            self.isSpotPassed = show
                            completion(show, false)
                            
                        } else {
                            print("Error: Spots or Checks or Visitor or Reccurence Condition Failed")
                            completion(false, false)
                        }
                        
                    } else {
                        print("Show not Received")
                    }
                    
                    if(self.isSpotPassed == false) {
                        
                        // Checks
                        if let checkPassed = json?["checkPassed"] as? Bool {
                            
                            if checkPassed == true {
                                
                                if let checkCondition = json?["checkCondition"] as? [String: Any] {
                                    if let afterDelay = checkCondition["afterDelay"] as? Double ?? Double(checkCondition["afterDelay"] as? String ?? "0") {
                                        self.afterDelay = afterDelay
                                    }
                                    if let customEvent = checkCondition["customEvent"] as? [String: Any] {
                                        self.customEventsSpotChecks = [(json ?? [:]) as [String: Any]]
                                        completion(false, false)
                                    } else {
                                        self.setAppearance(json: json ?? [:], screen: screen)
                                        self.isChecksPassed = checkPassed
                                        completion(checkPassed, false)
                                    }
                                }
                                
                            } else {
                                print("Error: Checks Condition Failed")
                                completion(false, false)
                            }
                        } else {
                            print("CheckPassed not Received")
                        }
                    }
                    
                    if(self.isSpotPassed == false && self.isChecksPassed == false){
                        
                        if let multiShow = json?["multiShow"] as? Bool {
                            
                            if multiShow == true {
                                
                                if let spotCheckList = json?["resultantSpotCheck"] as? [[String: Any]] {
                                    self.customEventsSpotChecks = spotCheckList
                                }
                                
                                var selectedSpotCheck: [String: Any] = [:]
                                var minDelay: Double = Double.greatestFiniteMagnitude
                                
                                for spotCheck in self.customEventsSpotChecks {
                                    
                                    if let checks:[String:Any] = spotCheck["checks"] as? [String : Any] {
                                        if checks.isEmpty {
                                            selectedSpotCheck = spotCheck
                                            break
                                        } else if let afterDelay = checks["afterDelay"] as? Double {
                                            let delay = Double(afterDelay) ?? Double.greatestFiniteMagnitude
                                            if minDelay > delay {
                                                minDelay = delay
                                                selectedSpotCheck = spotCheck
                                            }
                                        }
                                    }
                                    
                                }
                                
                                if !selectedSpotCheck.isEmpty {
                                    
                                    if let checkCondition = selectedSpotCheck["checks"] as? [String: Any],
                                        let aftrDelay = checkCondition["afterDelay"] as? Double  ?? Double(checkCondition["afterDelay"] as? String ?? "0") {
                                            self.afterDelay = aftrDelay
                                    }
                                    self.setAppearance(json: selectedSpotCheck, screen: screen)
                                    
                                    completion(true , true)
                                } else {
                                    completion(false , true)
                                    
                                }
                                
                            } else {
                                print("Error: MultiShow Condition Failed")
                                completion(false, false)
                            }
                            
                        }else {
                            print("MultiShow not Received")
                            completion(false, false)
                        }
                        
                    }
                }
                
            } catch {
                print("Error parsing JSON: \(error)")
                completion(false, false)
            }
            
        }.resume()
    }
    
    public func sendTrackEventRequest(screen: String, event: [String: Any], completion: @escaping (Bool) -> Void) {
        
        var selectedSpotCheckID = Int.max ;
        
        if self.customEventsSpotChecks.isEmpty {
            
            print("No Events in this screen")
            completion(false)
            
        } else {
            
            for spotCheck in self.customEventsSpotChecks {
                
                if let checks = spotCheck["checks"] as? [String: Any] ?? spotCheck["checkCondition"] as? [String: Any] ,
                   let customEvent:[String:Any] = checks["customEvent"] as? [String : Any] {
                    if let eventName = customEvent["eventName"] as? String {
                        if event.keys.contains(eventName) {
                            selectedSpotCheckID = spotCheck["id"] as? Int ?? spotCheck["spotCheckId"] as? Int ?? Int.max
                            
                            if selectedSpotCheckID != Int.max {
                                
                                if(
                                    self.userDetails["email"] == nil
                                    && self.userDetails["uuid"] == nil
                                    && self.userDetails["mobile"] == nil
                                ) {
                                    if let uuid = defaults.string(forKey: "SurveySparrowUUID"),
                                       !uuid.isEmpty {
                                        self.userDetails["uuid"] = uuid
                                    }
                                }

                                let payload: [String: Any] = [
                                    "screenName": screen ?? "",
                                    "variables": self.variables,
                                    "customProperties": self.customProperties,
                                    "traceId": self.traceId,
                                    "userDetails": self.userDetails,
                                    "visitor": [
                                        "deviceType": "MOBILE",
                                        "operatingSystem": "iOS",
                                        "screenResolution": [
                                            "width": UIScreen.main.bounds.width,
                                            "height": UIScreen.main.bounds.height
                                        ],
                                        "currentDate": self.getCurrentDate(),
                                        "timezone": TimeZone.current.identifier
                                    ],
                                    "spotCheckId": selectedSpotCheckID,
                                    "eventTrigger": [
                                        "customEvent": event,
                                    ]
                                ]
                                
                                guard let baseURL = URL(string: "https://\(self.domainName)/api/internal/spotcheck/widget/\(self.targetToken)/eventTrigger?isSpotCheck=true") else {
                                    print("Invalid URL")
                                    completion(false)
                                    return
                                }

                                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
                                components?.queryItems = [
                                    URLQueryItem(name: "isSpotCheck", value: "true")
                                ]

                                guard let url = components?.url else {
                                    print("Failed to create URL with query parameters")
                                    completion(false)
                                    return
                                }

                                var request = URLRequest(url: url)
                                request.httpMethod = "POST"
                                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                                var reqData: Data
                                do {
                                    reqData = try JSONSerialization.data(withJSONObject: payload)
                                } catch {
                                    print("Error serializing JSON: \(error)")
                                    completion(false)
                                    return
                                }
                                
                                URLSession.shared.uploadTask(with: request, from: reqData) { data, response, error in
                                    if let error = error {
                                        print("Error: \(error)")
                                        completion(false)
                                        return
                                    }
                                    
                                    guard let data = data else {
                                        print("No data received")
                                        completion(false)
                                        return
                                    }
                                    
                                    do {
                                        // Responce
                                        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                                        
                                        DispatchQueue.main.async {
                                            
                                            var isShowFalse:Bool = false
                                            
                                            if let show = json?["show"] as? Bool {
                                                
                                                if !show {
                                                    isShowFalse = true
                                                    print("Error: Spots or Checks or Visitor or Reccurence Condition Failed")
                                                    completion(false)
                                                } else {
                                                    self.setAppearance(json: json ?? [:], screen: screen)
                                                    print("Spots & Checks & Visitor & Reccurence Condition Passed")
                                                    completion(show)
                                                }
                                            }
                                            
                                            if !isShowFalse {
                                                if let eventShow = json?["eventShow"] as? Bool {
                                                    
                                                    if eventShow == true {
                                                        
                                                        if let checkCondition = json?["checkCondition"] as? [String: Any]{
                                                            if let aftrDelay = checkCondition["afterDelay"] as? Double ?? Double(checkCondition["afterDelay"] as? String ?? "0") {
                                                                self.afterDelay = aftrDelay
                                                            }
                                                            if let customEvent = checkCondition["customEvent"] as? [String: Any] {
                                                                if let aftrDelay = customEvent["delayInSeconds"] as? Double ??  Double(customEvent["delayInSeconds"] as? String ?? "0") {
                                                                    self.afterDelay = aftrDelay
                                                                }
                                                            }
                                                        }
                                                        self.setAppearance(json: json ?? [:], screen: screen)
                                                        print("EventShow Condition Passed ")
                                                        completion(eventShow)
                                                        
                                                    } else {
                                                        print("Error: EventShow Condition Failed")
                                                        completion(false)
                                                    }
                                                } else {
                                                    print("EventShow not Received")
                                                }
                                            }
                                        }
                                    } catch {
                                        print("Error parsing JSON: \(error)")
                                        completion(false)
                                    }
                                    
                                }.resume()
                                
                                break;
                            }else {
                                completion(false)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func setAppearance(json: [String: Any] = [:], screen: String) -> Void {
        
        let appearance = json["appearance"] as? [String: Any] ?? [:]
        let position = appearance["position"] as? String
        let cardProp = appearance["cardProperties"] as? [String: Any] ?? [:]
        let colors = appearance["colors"] as? [String: Any] ?? [:]
        let overrides = colors["overrides"] as? [String: String] ?? [:]
        var isChat: Bool = false
        let matchingSpotcheckId = "\(json["spotCheckId"] ?? json["id"] ?? 0)"
        
        let currentSpotCheck = self.filteredSpotChecks.first(where: {
            if let id = $0["id"] as? NSNumber {
                return id.stringValue == matchingSpotcheckId
            }
            return false
        })
        
        if let currentSpotCheck = currentSpotCheck,
           let survey = currentSpotCheck["survey"] as? [String: Any],
           let surveyType = survey["surveyType"] as? String {
            isChat = self.isChatSurvey(surveyType) && appearance["mode"] as? String == "fullScreen"
        }

        if position == "top_full" {
            self.spotcheckPosition = "top"
        } else if position == "center_center" {
            self.spotcheckPosition = "center"
        } else {
            self.spotcheckPosition = "bottom"
        }
        self.appearance = appearance
        self.isCloseButtonEnabled = appearance["closeButton"] as? Bool ?? true
        let maxHeightRaw = cardProp["maxHeight"]
        let mxHeight = maxHeightRaw as? Double ?? Double(maxHeightRaw as? String ?? "1") ?? 1
        self.maxHeight = mxHeight / 100
        print(self.isCloseButtonEnabled)
        self.closeButtonStyle = overrides
        self.isFullScreenMode = appearance["mode"] as? String == "fullScreen"
        self.spotChecksMode = appearance["mode"] as? String ?? ""
        self.isBannerImageOn = (appearance["bannerImage"] as? [String: Any])?["enabled"] as? Bool ?? false
        self.avatarEnabled = (appearance["avatar"] as? [String: Any])?["enabled"] as? Bool ?? false
        self.avatarUrl = (appearance["avatar"] as? [String: Any])?["avatarUrl"] as? String ?? ""
        self.spotCheckType = isChat ? "chat" : "classic"
        let isSpotCheckButton = (appearance["type"] as? String) == "spotcheckButton"
        
        if isSpotCheckButton {
            if let current = currentSpotCheck,
               let appearance = current["appearance"] as? [String: Any],
               let buttonConfig = appearance["buttonConfig"] as? [String: Any] {
                self.spotCheckButtonConfig = buttonConfig
            } else {
                self.spotCheckButtonConfig = [:]
            }
        } else {
            self.spotCheckButtonConfig = [:]
        }
        
        self.showSurveyContent = !isSpotCheckButton
        
        self.spotcheckID = (json["spotCheckId"] as? Int64) ?? (json["id"] as? Int64) ?? 0
        self.spotcheckContactID = (json["spotCheckContactId"] as? Int64)
        ?? (json["spotCheckContact"] as? [String: Any])?["id"] as? Int64 ?? 0
        self.triggerToken = json["triggerToken"] as? String ?? ""
        self.isChat = isChat
        self.screenName = screen
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.afterDelay)) {
            self.isSpotCheckButton = isSpotCheckButton
            if(!self.isSpotCheckButton){
                self.performBootstrapRequest()
            }
        } 
    }
    
    public func performBootstrapRequest() {
        
        let screen = self.screenName
        let isChat = self.isChat
        
        var baseURL = "https://\(self.domainName)/s/spotcheck/\(self.triggerToken)/\(isChat ? "config" : "bootstrap")"
        baseURL += "?spotcheckContactId=\(self.spotcheckContactID)&traceId=\(self.traceId)&spotcheckUrl=\(screen)"
        self.variables.forEach { key, value in
            baseURL += "&\(key)=\(value)"
        }
        
        self.spotcheckURL = baseURL
        guard let url = URL(string: baseURL) else { return }
        
        var userAgentString: String = ""

        getUserAgent { userAgent in
            userAgentString = userAgent
        }

        var request = URLRequest(url: url)
        request.setValue(userAgentString, forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            guard error == nil else {
                return
            }
            
            guard let data = data else {
                return
            }


            guard let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            
            var themeCSS: [String: Any]? = [:]
            if let config = jsonObj["config"] as? [String: Any] {
                themeCSS = config["generatedCSS"] as? [String: Any]
            }
            
            let appearanceDict = self.appearance ?? [:]
            
            var injectedData: [String: Any] = [
                "type": "RESET_STATE",
                "state": [
                    
                    "skip": true,
                    "spotCheckAppearance": appearanceDict,
                    "spotcheckUrl": screen,
                    "traceId": self.traceId,
                    "elementBuilderParams": self.variables,
                    "targetType": "MOBILE"
                ]
            ]
            

            if var state = injectedData["state"] as? [String: Any] {
                state.merge(jsonObj) { _, new in new }
                injectedData["state"] = state
            } else {
                injectedData["state"] = jsonObj
            }

            let themePayload: [String: Any] = [
                "type": "THEME_UPDATE_SPOTCHECK",
                "themeInfo": themeCSS
            ]
            DispatchQueue.main.async{
                
                if(isChat){
                    self.injectionJS = """
                (function() {
                    window.dispatchEvent(new MessageEvent('message', { data: \(self.jsonString(from: injectedData)) }));
                })();
                """
                }else{
                    self.injectionJS = """
                (function() {
                    window.dispatchEvent(new MessageEvent('message', { data: \(self.jsonString(from: injectedData)) }));
                    window.dispatchEvent(new MessageEvent('message', { data: \(self.jsonString(from: themePayload)) }));
                })();
                """
                }
                
                
                if isChat {
                    if !self.isChatLoading {
                        self.chatBool = true
                        self.chatWebView?.evaluateJavaScript(self.injectionJS)
                        self.start()
                    }
                } else {
                    if !self.isClassicLoading {
                        self.classicBool = true
                        self.classicWebView?.evaluateJavaScript(self.injectionJS)
                        self.start()
                    }
                }
                
            }
        }.resume()

    }

    private func jsonString(from dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
    
    private func currentSurveyType() -> String {
        return self.spotCheckType ?? ""
    }

        
    public func getCurrentDate() -> String {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let currentDateStr = dateFormatter.string(from: currentDate)
        return currentDateStr
    }
    
    public func closeSpotCheck() {
        
        let payload: [String: String] = [
            "traceId": self.traceId,
            "triggerToken": self.triggerToken
        ]
        
        guard let url = URL(string: "https://\(self.domainName)/api/internal/spotcheck/dismiss/\(self.spotcheckContactID)") else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var reqData: Data
        do {
            reqData = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("Error serializing JSON: \(error)")
            return
        }
        
        URLSession.shared.uploadTask(with: request, from: reqData) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                if(((json?["success"]) != nil) == true){
                    Task{
                        await self.surveyDelegate.handleCloseButtonTap();
                    }
                    print("SpotCheck Closed")
                }
            }catch {
                print("Error parsing JSON: \(error)")
                
            }
        }.resume()
    }
    
    func generateTraceId() -> String {
        let uuid = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(uuid)-\(timestamp)"
    }  
}
