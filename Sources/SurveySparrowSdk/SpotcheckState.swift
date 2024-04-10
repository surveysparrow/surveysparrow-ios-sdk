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
    var email: String
    var firstName: String
    var lastName: String
    var phoneNumber: String
    
    public init(email: String , firstName: String = "", lastName: String = "", phoneNumber: String = "") {
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        
        self.updateLocation { success in
            if success {
                print("Location updated successfully.")
            } else {
                print("Failed to update location.")
            }
        }
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
    
    @StateObject var locationManager = LocationManager()
    
    public var userLatitude: String {
        guard let latitude = locationManager.lastLocation?.coordinate.latitude else {
            return "Unknown"
        }
        return "\(latitude)"
    }
    
    public var userLongitude: String {
        guard let longitude = locationManager.lastLocation?.coordinate.longitude else {
            return "Unknown"
        }
        return "\(longitude)"
    }
    
    
    public func updateLocation(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            self.locationManager.requestLocation()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { // Adjust the delay as needed
            print(self.locationManager.lastLocation)
            if let latitude = self.locationManager.lastLocation?.coordinate.latitude,
               let longitude = self.locationManager.lastLocation?.coordinate.longitude {
                completion(true)
            } else {
                print("Failed to get location.")
                completion(false)
            }
        }
    }
    
    public func sendRequest(screen: String?, event: String?, completion: @escaping (Bool) -> Void) {
        updateLocation { success in
            guard success else {
                completion(false)
                return
            }
            let payload: [String: Any] = [
                "url": screen ?? "",
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
                            "latitude" : self.userLatitude,
                            "longitude" : self.userLongitude
                        ]
                    ],
                    "ipAddress": self.fetchIPAddress() ?? "",
                    "deviceType": UIDevice.current.model,
                    "operatingSystem": UIDevice.current.systemName,
                    "browser": "",
                    "browserLanguage": "",
                    "screenResolution": [
                        "width": UIScreen.main.bounds.width,
                        "height": UIScreen.main.bounds.height
                    ],
                    "userAgent": "",
                    "currentDate": self.getCurrentDate(),
                    "timezone": TimeZone.current.identifier
                ]
            ]
            guard let url = URL(string: "https://53b4-183-82-247-142.ngrok-free.app/api/internal/spotcheck/widget/tar-1/properties") else {
                print("Invalid URL")
                completion(false)
                return
            }
            print(payload)
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
                print(data)
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    if let valid = json?["checkPassed"] as? Bool {
                        print("valid",valid)
                        completion(valid)
                    } else {
                        print("Invalid response format")
                        completion(false)
                    }
                } catch {
                    print("Error parsing JSON: \(error)")
                    completion(false)
                }
                
            }.resume()
        }
    }
}
