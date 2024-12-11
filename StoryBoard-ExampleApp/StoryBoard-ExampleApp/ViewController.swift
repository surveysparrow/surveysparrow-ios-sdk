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
    domainName: "gokulkrishnaraju1183.surveysparrow.com",
    targetToken: "tar-fkwYzrxBCD4yBzdkFfCmVW",
    userDetails: [:]
)

@available(iOS 15.0, *)
class ViewController: UIViewController {}


@available(iOS 15.0, *)
class HomeScreen: UIViewController {
    
    var hostingController: UIHostingController<Spotcheck>?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        spotCheck.TrackScreen(screen: "PaymentScreen")
        
        let hostingController = UIHostingController(rootView: spotCheck)
        self.hostingController = UIHostingController(rootView: spotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }
    
    
    @IBAction func Click(_ sender: UIButton) {
        spotCheck.TrackEvent(onScreen: "PaymentScreen", event: ["MobileClick": []])
        
        let hostingController = UIHostingController(rootView: spotCheck)
        self.hostingController = UIHostingController(rootView: spotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }
    
}

@available(iOS 15.0, *)
class SettingScreen: UIViewController {
    
    var hostingController: UIHostingController<Spotcheck>?
    
    @IBAction func settingScreenAction(_ sender: UIButton) {
        spotCheck.TrackEvent(onScreen: "SettingScreen", event: ["SettingScreenAction": []])
        
        let hostingController = UIHostingController(rootView: spotCheck)
        self.hostingController = UIHostingController(rootView: spotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        spotCheck.TrackScreen(screen: "SettingScreen")
        
        let hostingController = UIHostingController(rootView: spotCheck)
        self.hostingController = UIHostingController(rootView: spotCheck)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        present(hostingController, animated: true, completion: nil)
    }
    
}
