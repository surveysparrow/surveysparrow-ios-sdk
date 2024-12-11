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
    domainName: "gokulkrishnaraju1183.surveysparrow.com",
    targetToken: "tar-fkwYzrxBCD4yBzdkFfCmVW",
    userDetails: [:]
)

@available(iOS 15.0, *)
class TabViewController: UIViewController {}


@available(iOS 15.0, *)
class TabHomeScreen: UIViewController {
    
    var hostingController: UIHostingController<Spotcheck>?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tabSpotCheck.TrackScreen(screen: "TabHomeScreen")
        print("TrackScreen-TabHomeScreen")
        
        let hostingController = UIHostingController(rootView: tabSpotCheck)
        self.hostingController = UIHostingController(rootView: tabSpotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }
    
    
    @IBAction func Click(_ sender: UIButton) {
        tabSpotCheck.TrackEvent(onScreen: "TabHomeScreen", event: ["TabHomeScreenAction": []])
        
        let hostingController = UIHostingController(rootView: tabSpotCheck)
        self.hostingController = UIHostingController(rootView: tabSpotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }
    
}

@available(iOS 15.0, *)
class TabSettingScreen: UIViewController {
    
    var hostingController: UIHostingController<Spotcheck>?

    @IBAction func settingScreenAction(_ sender: UIButton) {
        tabSpotCheck.TrackEvent(onScreen: "TabSettingScreen", event: ["TabSettingScreenAction": []])
        
        let hostingController = UIHostingController(rootView: tabSpotCheck)
        self.hostingController = UIHostingController(rootView: tabSpotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tabSpotCheck.TrackScreen(screen: "TabSettingScreen")
        
        let hostingController = UIHostingController(rootView: tabSpotCheck)
        self.hostingController = UIHostingController(rootView: tabSpotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }
    
}
