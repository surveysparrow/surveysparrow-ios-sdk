//
//  ViewController.swift
//  StoryBoard-ExampleApp
//
//  Created by Gokulkrishna raju on 31/01/24.
//

import UIKit
import SurveySparrowSdk
import SwiftUI

@available(iOS 15.0, *)
var spotCheck = Spotcheck(
    domainName: "",
    targetToken: "",
    userDetails: [:],
    surveyDelegate: SsDelegate(),
    isUIKitApp: true
)

@available(iOS 15.0, *)
class ViewController: UIViewController {}


@available(iOS 15.0, *)
class HomeScreen: UIViewController {
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        
        spotCheck.TrackScreen(screen: "PaymentScreen") {
            trackScreenPassed in
            if trackScreenPassed {
                let hostingController = UIHostingController(rootView: spotCheck)
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.view.backgroundColor = UIColor.clear
                self.present(hostingController, animated: true, completion: {})
            }
        }
    }
    
    @IBAction func Click(_ sender: UIButton) {
        spotCheck.TrackEvent(onScreen: "PaymentScreen", event: ["MobileClick": []]){
            trackScreenPassed in
            if trackScreenPassed {
                let hostingController = UIHostingController(rootView: spotCheck)
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.view.backgroundColor = UIColor.clear
                self.present(hostingController, animated: true, completion: {})
            }
        }
    }
}

@available(iOS 15.0, *)
class SettingScreen: UIViewController {
    
    var hostingController: UIHostingController<Spotcheck>?
    
    @IBAction func settingScreenAction(_ sender: UIButton) {
        spotCheck.TrackEvent(onScreen: "SettingScreen", event: ["SettingScreenAction": []]){
            trackScreenPassed in
            if trackScreenPassed {
                let hostingController = UIHostingController(rootView: spotCheck)
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.view.backgroundColor = UIColor.clear
                self.present(hostingController, animated: true, completion: {})
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        spotCheck.TrackScreen(screen: "SettingScreen"){
            trackScreenPassed in
            if trackScreenPassed {
                let hostingController = UIHostingController(rootView: spotCheck)
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.view.backgroundColor = UIColor.clear
                self.present(hostingController, animated: true, completion: {})
            }
        }
    }
    
}

@available(iOS 15.0, *)
class SsDelegate: UIViewController, SsSpotcheckDelegate {

    func handleSurveyResponse(response: [String : AnyObject]) async {
        print("Received survey response: ", response)
    }
    
    func handlePartialSubmission(response: [String : AnyObject]) async {
        print("Received partial Submission: ", response)
    }

    func handleSurveyLoaded(response: [String : AnyObject]) async {
        print("Survey Loaded: ", response)
    }

    func handleCloseButtonTap() async {
        print("Survey closed by the User.")
    }
}
