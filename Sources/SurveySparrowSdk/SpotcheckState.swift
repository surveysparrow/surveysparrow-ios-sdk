//
//  SpotcheckState.swift
//
//
//  Created by Gokulkrishna raju on 03/04/24.
//

import SwiftUI
import CoreLocation

@available(iOS 15.0, *)
public class SpotcheckState: ObservableObject {
    
    @Published public var isValid: Bool = false
    @Published public var offset: CGFloat = 1000
    @Published public var position: String = ""
    @Published public var spotcheckURL: String = ""
    @Published public var spotcheckID: Int64 = 0
    @Published public var spotcheckContactID: Int64 = 0
    @Published public var afterDelay: Double = 0
    @Published public var isCloseButtonEnabled: Bool = false
    
    @Published private var isSpotPassed: Bool = false
    @Published private var isChecksPassed: Bool = false
    @Published private var multiShowSpotCheck: [[String: Any]] = [[:]]
    
    var email: String
    var firstName: String
    var lastName: String
    var phoneNumber: String
    var targetToken: String
    var domainName: String
    var latitude: Double
    var longitude: Double
    
    public init(email: String, targetToken:String, domainName: String, firstName: String = "", lastName: String = "", phoneNumber: String = "", location: [String: Double]) {
        self.email = email
        self.targetToken = targetToken
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.domainName = domainName
        self.latitude = location["latitude"] ?? 0.0
        self.longitude = location["longitude"] ?? 0.0
    }
    
    
    public func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation(.spring()) {
                self.offset = 0
            }
        }
    }
    
    public func end() {
        withAnimation(.spring()) {
            offset = 1000
        }
    }
    
    
    public func sendRequest(screen: String?, event: String?, completion: @escaping (Bool, Bool) -> Void) {
        
        let payload: [String: Any] = [
            "screenName": screen ?? "",
            "variables": [:],
            "userDetails": [
                "email": self.email,
                "firstName": self.firstName,
                "lastName": self.lastName,
                "phoneNumber": self.phoneNumber
            ],
            "visitor": [
                "location": [
                    "coords": [
                        "latitude" : latitude,
                        "longitude" : longitude,
                    ]
                ],
                "ipAddress": self.fetchIPAddress() ?? "",
                "deviceType": "Mobile",
                "operatingSystem": UIDevice.current.systemName,
                "screenResolution": [
                    "width": UIScreen.main.bounds.width,
                    "height": UIScreen.main.bounds.height
                ],
                "currentDate": self.getCurrentDate(),
                "timezone": TimeZone.current.identifier
            ],
            //            "eventTrigger": [
            //                "customEvent": [ "buy": [ "amount": 500 ] ],
            //            ]
        ]
        
        var url: URL?
        
        //        , let event = event,
        if let screen = screen, !screen.isEmpty {
            url = URL(string: "https://\(self.domainName)/api/internal/spotcheck/widget/\(self.targetToken)/properties")
        }
        //        else {
        //            url = URL(string: "https://\(self.domainName)/api/internal/spotcheck/widget/\(self.targetToken)/eventTrigger")
        //        }
        
        guard let finalURL = url else {
            print("Invalid URL")
            completion(false, false)
            return
        }
        
        print(payload)
        var request = URLRequest(url: finalURL)
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
                
                DispatchQueue.main.async {
                    
                    if let show = json?["show"] as? Bool {
                        
                        if show == true {
                            
                            
                            self.spotcheckID = json?["spotCheckId"] as! Int64
                            self.spotcheckContactID = json?["spotCheckContactId"] as! Int64
                            self.spotcheckURL = "https://\(self.domainName)/n/spotcheck/\(self.spotcheckID)?spotcheckContactId=\(self.spotcheckContactID)"
                            
                            if let appearance = json?["appearance"] as? [String: Any],
                               let position = appearance["position"] as? String,
                               let isCloseButtonEnabled = appearance["closeButton"] as? Bool {
                                if position == "top_full" {self.position = "top"}
                                if position == "center_center" {self.position = "center"}
                                if position == "bottom_full" {self.position = "bottom"}
                                self.isCloseButtonEnabled = isCloseButtonEnabled ?? false
                            }
                            
                            self.isSpotPassed = show
                            
                            completion(show, false)
                            
                        } else {
                            print("Error: Spots or Checks or Visitor or Reccurence Condition Failed")
                            completion(false, false)
                        }
                        
                    } else {
                        print("Error: Show not Received")
                        completion(false, false)
                    }
                    
                    if(self.isSpotPassed == false){
                        
                        // Checks
                        if let checkPassed = json?["checkPassed"] as? Bool {
                            
                            if checkPassed == true {
                                
                                self.spotcheckID = json?["spotCheckId"] as! Int64
                                self.spotcheckContactID = json?["spotCheckContactId"] as! Int64
                                self.spotcheckURL = "https://\(self.domainName)/n/spotcheck/\(self.spotcheckID)?spotcheckContactId=\(self.spotcheckContactID)"
                                
                                if let checkCondition = json?["checkCondition"] as? [String: Any]{
                                    let afterDelay = checkCondition["afterDelay"] as? String
                                    if let afterDelayDouble = Double(afterDelay ?? "0") {
                                        self.afterDelay = afterDelayDouble
                                    }
                                }
                                
                                if let appearance = json?["appearance"] as? [String: Any],
                                   let position = appearance["position"] as? String,
                                   let isCloseButtonEnabled = appearance["closeButton"] as? Bool {
                                    if position == "top_full" {self.position = "top"}
                                    if position == "center_center" {self.position = "center"}
                                    if position == "bottom_full" {self.position = "bottom"}
                                    self.isCloseButtonEnabled = isCloseButtonEnabled ?? false
                                }
                                
                                self.isChecksPassed = checkPassed
                                completion(checkPassed, false)
                                
                            } else {
                                print("Error: Checks Condition Failed")
                                completion(false, false)
                            }
                        } else {
                            print("Error: CheckPassed not Received")
                            completion(false, false)
                        }
                    }
                    
                    if(self.isSpotPassed == false && self.isChecksPassed == false){
                        
                        if let multiShow = json?["multiShow"] as? Bool {
                            
                            if multiShow == true {
                                
                                if let spotCheckList = json?["resultantSpotCheck"] as? [[String: Any]], !spotCheckList.isEmpty {
                                    self.multiShowSpotCheck = spotCheckList
                                }
                                
                                for spotCheck in self.multiShowSpotCheck {
                                    
                                    if let spots:[String:Any] = spotCheck["spots"] as? [String : Any] {
                                        if let includedSpotList: [[String:Any]] = spots["include"] as? [[String : Any]] {
                                            for includedSpot in includedSpotList {
                                                if includedSpot["value"] as? String == screen {
                                                    
//                                                    self.spotcheckID = spotCheck["id"] as! Int64
//                                                    self.spotcheckContactID = spotCheck["spotCheckContactId"] as! Int64
//                                                    self.spotcheckURL = "https://\(self.domainName)/n/spotcheck/\(self.spotcheckID)?spotcheckContactId=\(self.spotcheckContactID)"
//                                                    
//                                                    if let checkCondition = spotCheck["checkCondition"] as? [String: Any]{
//                                                        let afterDelay = checkCondition["afterDelay"] as? String
//                                                        if let afterDelayDouble = Double(afterDelay ?? "0") {
//                                                            self.afterDelay = afterDelayDouble
//                                                        }
//                                                    }
//                                                    
//                                                    if let appearance = spotCheck["appearance"] as? [String: Any],
//                                                       let position = appearance["position"] as? String,
//                                                       let isCloseButtonEnabled = appearance["closeButton"] as? Bool {
//                                                        if position == "top_full" {self.position = "top"}
//                                                        if position == "center_center" {self.position = "center"}
//                                                        if position == "bottom_full" {self.position = "bottom"}
//                                                        self.isCloseButtonEnabled = isCloseButtonEnabled ?? false
//                                                    }
                                                    
                                                    completion(true , true)
//                                                    self.start()
                                                }
                                            }
                                        }
                                    }
                                }
                                
                            } else {
                                print("Error: MultiShow Condition Failed")
                                completion(false, false)
                            }
                            
                        }else {
                            print("Error: MultiShow not Received")
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
    
    public func fetchIPAddress() -> String? {
        var address : String?
        
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                if  name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                } else if (name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(1), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        
        return address
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
        
        guard let url = URL(string: "https://\(self.domainName)/api/internal/spotcheck/dismiss/\(self.spotcheckContactID)") else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    
        URLSession.shared.dataTask(with: request) { data, response, error in
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
                    print("Successfully Closed")
                }
            }catch {
                print("Error parsing JSON: \(error)")

            }
        }.resume()
    }
    
}
