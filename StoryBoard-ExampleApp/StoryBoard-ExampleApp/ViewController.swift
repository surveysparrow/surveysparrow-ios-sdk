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
var spotCheck: Spotcheck = {
    let spotCheck = Spotcheck(
        domainName: "gokulkrishnaraju1183.surveysparrow.com",
        targetToken: "tar-fkwYzrxBCD4yBzdkFfCmVW",
        userDetails: [:]
    )
    return spotCheck
}()

@available(iOS 15.0, *)
class ViewController: UIViewController, SsSurveyDelegate {
    var hostingController: UIHostingController<Spotcheck>?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Only present the hostingController when the view has appeared
        if hostingController == nil {
            let hostingController = UIHostingController(rootView: spotCheck)
            self.hostingController = hostingController
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.view.backgroundColor = UIColor.clear
            spotCheck.hostingController = hostingController
            
            // Ensure presentation occurs when the view is ready
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = scene.windows.first?.rootViewController {
                rootViewController.present(hostingController, animated: true, completion: {print("Presented")})
                hostingController.dismiss(animated: true, completion: {print("Dismissed")})
            } else {
                print("Error: Root view controller not found")
            }
        }
    }

    func handleSurveyResponse(response: [String: AnyObject]) {
        print(response)
    }
    
    func handleSurveyLoaded(response: [String: AnyObject]) {
        print(response)
    }
    
    func handleSurveyValidation(response: [String: AnyObject]) {
        print(response)
    }
    
    func handleCloseButtonTap() {
        print("Close Button Tapped")
    }
}


@available(iOS 15.0, *)
class HomeScreen: UIViewController {

    @IBAction func homeScreenAction(_ sender: UIButton) {
        spotCheck.TrackEvent(onScreen: "HomeScreen", event: ["HomeScreenAction": []])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        spotCheck.TrackScreen(screen: "HomeScreen")
    }
    
}

@available(iOS 15.0, *)
class SettingScreen: UIViewController {

    @IBAction func settingScreenAction(_ sender: UIButton) {
        spotCheck.TrackEvent(onScreen: "SettingScreen", event: ["SettingScreenAction": []])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        spotCheck.TrackScreen(screen: "SettingScreen")
    }
    
}

