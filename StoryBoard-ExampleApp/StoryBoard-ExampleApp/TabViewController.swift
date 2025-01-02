//
//  TabViewController.swift
//  StoryBoard-ExampleApp
//
//  Created by Gokulkrishna Raju on 11/12/24.
//

import Foundation


import UIKit
import SurveySparrowSdk
import SwiftUI

@available(iOS 15.0, *)
var tabSpotCheck = Spotcheck(
    domainName: "",
    targetToken: "",
    userDetails: [:],
    surveyDelegate: SsDelegate(),
    isUIKitApp: true
)

@available(iOS 15.0, *)
class TabViewController: UIViewController {}


@available(iOS 15.0, *)
class TabHomeScreen: UIViewController {
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tabSpotCheck.TrackScreen(screen: "TabHomeScreen"){
            trackScreenPassed in
            if trackScreenPassed {
                let hostingController = UIHostingController(rootView: tabSpotCheck)
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.view.backgroundColor = UIColor.clear
                self.present(hostingController, animated: true, completion: {})
            }
        }
    }
    
    
    @IBAction func Click(_ sender: UIButton) {
        
        tabSpotCheck.TrackEvent(onScreen: "TabHomeScreen", event: ["TabHomeScreenAction": []]){
            trackScreenPassed in
            if trackScreenPassed {
                let hostingController = UIHostingController(rootView: tabSpotCheck)
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.view.backgroundColor = UIColor.clear
                self.present(hostingController, animated: true, completion: {})
            }
        }
    }
    
}

@available(iOS 15.0, *)
class TabSettingScreen: UIViewController {
    
    @IBAction func settingScreenAction(_ sender: UIButton) {
        tabSpotCheck.TrackEvent(onScreen: "TabSettingScreen", event: ["TabSettingScreenAction": []]){
            trackScreenPassed in
            if trackScreenPassed {
                let hostingController = UIHostingController(rootView: tabSpotCheck)
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.view.backgroundColor = UIColor.clear
                self.present(hostingController, animated: true, completion: {})
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tabSpotCheck.TrackScreen(screen: "TabSettingScreen"){
            trackScreenPassed in
            if trackScreenPassed {
                let hostingController = UIHostingController(rootView: tabSpotCheck)
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.view.backgroundColor = UIColor.clear
                self.present(hostingController, animated: true, completion: {})
            }
        }
    }
    
}
