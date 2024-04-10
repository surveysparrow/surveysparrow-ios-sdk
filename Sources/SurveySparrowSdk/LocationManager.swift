import SwiftUI
import CoreLocation

@available(iOS 13.0, *)
public class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()
    @Published var locationStatus: CLAuthorizationStatus?
    @Published var lastLocation: CLLocation?

    public override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // Check if location services are enabled
        if CLLocationManager.locationServicesEnabled() {
            self.locationManager.requestWhenInUseAuthorization()
            self.locationManager.startUpdatingLocation()
        } else {
            print("Location services are not enabled")
            // Handle the case where location services are disabled
        }
    }

    var statusString: String {
        guard let status = locationStatus else {
            return "Unknown"
        }
        
        switch status {
        case .notDetermined: return "Not Determined"
        case .authorizedWhenInUse: return "Authorized When In Use"
        case .authorizedAlways: return "Authorized Always"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        default: return "Unknown"
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            print("Error: \(error.localizedDescription)")
        }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.locationStatus = status
        print("Location authorization status changed: \(statusString)")
        if status == .denied || status == .restricted {
            // Handle denied or restricted authorization status
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print(locations.last)
        guard let location = locations.last else {
            print("Failed to get location")
            return
        }
        
        self.lastLocation = location
        print("Location updated: \(location)")
    }
    
    public func requestLocation() {
        self.locationManager.requestLocation()
    }
}

//
//public class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
//    
//    private let locationManager = CLLocationManager()
//    @Published public var locationStatus: CLAuthorizationStatus?
//    @Published public var lastLocation: CLLocation?
//    
//    public override init() {
//        super.init()
//        self.locationManager.delegate = self
//    }
//    
//    public var statusString: String {
//        guard let status = locationStatus else {
//            return "Unknown"
//        }
//        
//        switch status {
//        case .notDetermined: return "Not Determined"
//        case .authorizedWhenInUse: return "Authorized When In Use"
//        case .authorizedAlways: return "Authorized Always"
//        case .restricted: return "Restricted"
//        case .denied: return "Denied"
//        default: return "Unknown"
//        }
//    }
//    
//    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
//        print("Error: \(error.localizedDescription)")
//    }
//    
//    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
//        self.locationStatus = status
//        print("Location authorization status changed: \(statusString)")
//        if status == .denied || status == .restricted {
//            print("Location services denied or restricted.")
//        } else {
//            requestLocation()
//        }
//    }
//    
//    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        guard let location = locations.last else {
//            print("Failed to get location.")
//            return
//        }
//        self.lastLocation = location
//        print("Location updated: \(location)")
//    }
//    
//    public func requestLocation() {
//        DispatchQueue.main.async {
//            if CLLocationManager.locationServicesEnabled() {
//                switch CLLocationManager.authorizationStatus() {
//                case .notDetermined:
//                    self.locationManager.requestWhenInUseAuthorization()
//                case .authorizedWhenInUse, .authorizedAlways:
//                    self.locationManager.startUpdatingLocation()
//                case .restricted, .denied:
//                    print("Location services denied or restricted.")
//                @unknown default:
//                    print("Unknown authorization status.")
//                }
//            } else {
//                print("Location services are not enabled.")
//            }
//        }
//    }
//}
