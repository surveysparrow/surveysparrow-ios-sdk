//
//  SpotcheckState.swift
//
//
//  Created by Gokulkrishna raju on 03/04/24.
//

import SwiftUI
import CoreLocation

@available(iOS 13.0, *)
public class SpotcheckState: ObservableObject {
    
    @Published public var isVisible = false
    @Published public var position: String = ""
    @Published public var spotcheckURL: String = ""
    @Published public var spotcheckID: Int64 = 0
    @Published public var spotcheckContactID: Int64 = 0
    @Published public var afterDelay: Double = 0
    @Published public var maxHeight: Double = 0.5
    @Published public var currentQuestionHeight: Double = 0
    @Published public var isFullScreenMode: Bool = true
    @Published public var isBannerImageOn: Bool = false
    @Published public var triggerToken: String = ""
    @Published public var closeButtonStyle: [String: String] = [:]
    @Published public var isCloseButtonEnabled: Bool = false
    
    @Published private var isSpotPassed: Bool = false
    @Published private var isChecksPassed: Bool = false
    @Published private var customEventsSpotChecks: [[String: Any]] = []
    
    var targetToken: String
    var domainName: String
    var userDetails: [String: Any]
    var variables: [String: Any]
    var customProperties: [String: Any]
    var traceId: String = ""
    let defaults = UserDefaults.standard
    
    public init(targetToken:String, domainName: String, userDetails: [String: Any], variables: [String: Any], customProperties: [String: Any]) {
        self.targetToken = targetToken
        self.domainName = domainName
        self.userDetails = userDetails
        self.variables = variables
        self.customProperties = customProperties
        if self.traceId.isEmpty {
            self.traceId = generateTraceId()
            if defaults.string(forKey: "SurveySparrowUUID") == nil {
                defaults.set("", forKey: "SurveySparrowUUID")
            }
        }
    }
    
    
    public func start() {
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            self.isVisible = true
        }
    }
    
    public func end() {
        self.isVisible = false
        self.spotcheckID = 0
        self.position = ""
        self.currentQuestionHeight = 0
        self.spotcheckContactID = 0
        self.spotcheckURL = ""
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
                "deviceType": "Mobile",
                "operatingSystem": "iOS",
                "screenResolution": [
                    "width": UIScreen.main.bounds.width,
                    "height": UIScreen.main.bounds.height
                ],
                "currentDate": self.getCurrentDate(),
                "timezone": TimeZone.current.identifier
            ]
        ]
        
        guard let baseURL = URL(string: "https://\(self.domainName)/api/internal/spotcheck/widget/\(self.targetToken)/properties") else {
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
                                    if let afterDelay = checkCondition["afterDelay"] as? String,
                                       let afterDelayDouble = Double(afterDelay ?? "0") {
                                        self.afterDelay = afterDelayDouble
                                    }
                                    if let customEvent = checkCondition["customEvent"] as? [String: Any] {
                                        self.customEventsSpotChecks = [(json ?? [:]) as [String: Any]]
                                        completion(false, false)
                                    }else {
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
                                        } else if let afterDelay = checks["afterDelay"] as? String {
                                            let delay = Double(afterDelay) ?? Double.greatestFiniteMagnitude
                                            if minDelay > delay {
                                                minDelay = delay
                                                selectedSpotCheck = spotCheck
                                            }
                                        }
                                    }
                                    
                                }
                                
                                if !selectedSpotCheck.isEmpty {
                                    
                                    if let checkCondition = selectedSpotCheck["checks"] as? [String: Any] {
                                        let afterDelay = checkCondition["afterDelay"] as? String
                                        if let afterDelayDouble = Double(afterDelay ?? "0") {
                                            self.afterDelay = afterDelayDouble
                                        }
                                    }
                                    self.setAppearance(json: selectedSpotCheck, screen: screen)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + self.afterDelay) {
                                        self.start()
                                    }
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
                                        "deviceType": "Mobile",
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
                                
                                guard let baseURL = URL(string: "https://\(self.domainName)/api/internal/spotcheck/widget/\(self.targetToken)/eventTrigger") else {
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
                                                            if let afterDelay = checkCondition["afterDelay"] as? String,
                                                            let afterDelayDouble = Double(afterDelay ?? "0") {
                                                                self.afterDelay = afterDelayDouble
                                                            }
                                                            if let customEvent = checkCondition["customEvent"] as? [String: Any] {
                                                                if let afterDelay = customEvent["delayInSeconds"] as? String,
                                                                let afterDelayDouble = Double(afterDelay ?? "0") {
                                                                    self.afterDelay = afterDelayDouble
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
                            }
                            
                            else {
                                completion(false)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func setAppearance(json: [String: Any] = [:], screen: String) -> Void {
        if let appearance = json["appearance"] as? [String: Any],
           let position = appearance["position"] as? String,
           let isCloseButtonEnabled = appearance["closeButton"] as? Bool,
           let cardProp = appearance["cardProperties"] as? [String: Any],
           let colors = appearance["colors"] as? [String: Any],
           let overrides = colors["overrides"] as? [String: String] {
            if position == "top_full" {self.position = "top"}
            else if position == "center_center" {self.position = "center"}
            else if position == "bottom_full" {self.position = "bottom"}
            self.isCloseButtonEnabled = isCloseButtonEnabled ?? false
            let mxHeight = cardProp["maxHeight"] as? Double ?? Double(cardProp["maxHeight"] as? String ?? "1") ?? 1
            self.maxHeight = mxHeight / 100
            self.closeButtonStyle = overrides
            self.isFullScreenMode = appearance["mode"] as? String == "fullScreen" ? true : false
            if let bannerImage = appearance["bannerImage"] as? [String: Any],
               let enabled = bannerImage["enabled"] as? Bool {
                self.isBannerImageOn = enabled
            }
        }
        
        self.spotcheckID = (json["spotCheckId"] as? Int64) ?? (json["id"] as? Int64) ?? 0
        self.spotcheckContactID = (json["spotCheckContactId"] as? Int64) ?? 0
        if self.spotcheckContactID == 0,
           let spotCheckContact = json["spotCheckContact"] as? [String: Any],
           let contactID = spotCheckContact["id"] as? Int64 {
            self.spotcheckContactID = contactID
        }
        
        self.triggerToken = json["triggerToken"] as! String
        self.spotcheckURL = "https://\(self.domainName)/n/spotcheck/\(self.triggerToken)?spotcheckContactId=\(self.spotcheckContactID)&traceId=\(self.traceId)&spotcheckUrl=\(screen)"
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
