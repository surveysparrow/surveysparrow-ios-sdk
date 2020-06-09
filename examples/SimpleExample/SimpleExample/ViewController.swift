//
//  ViewController.swift
//  SimpleExample
//
//  Created by Ajay Sivan on 09/06/20.
//  Copyright © 2020 SurveySparrow. All rights reserved.
//

import UIKit
import SurveySparrowSdk

class ViewController: UIViewController, SsSurveyDelegate {
  // MARK: Connection
  @IBOutlet weak var ssSurveyView: SsSurveyView!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    
    let surveySparrow = SurveySparrow(domain: "<account-domain>", token: "<sdk-token>")
    surveySparrow.scheduleSurvey(parent: self)
  }

  // MARK: Actions
  @IBAction func startFullscreenSurvey(_ sender: UIButton) {
    let ssSurveyViewController = SsSurveyViewController()
    ssSurveyViewController.domain = "<account-domain>"
    ssSurveyViewController.token = "<sdk-token>"
    ssSurveyViewController.surveyDelegate = self
    present(ssSurveyViewController, animated: true, completion: nil)
  }
  
  @IBAction func showEmbeddedSurvey(_ sender: UIButton) {
    ssSurveyView.loadSurvey()
  }
  
  func handleSurveyResponse(response: [String : Any]) {
    print(response)
  }
}

