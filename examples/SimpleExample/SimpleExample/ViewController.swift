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
    surveySparrow.params = ["emailaddress":"email@email.com","email":"email@email.com"]
    surveySparrow.scheduleSurvey(parent: self)
  }
  //    tt-9EBCDyTxxyguLKMh9MJaTt
  // MARK: Actions
  @IBAction func startFullscreenSurvey(_ sender: UIButton) {
    let ssSurveyViewController = SsSurveyViewController()
    ssSurveyViewController.domain = "<account-domain>"
    ssSurveyViewController.token = "<sdk-token>"
    ssSurveyViewController.params = ["emailaddress":"email@email.com","email":"email@email.com"]
    ssSurveyViewController.getSurveyLoadedResponse = true
    ssSurveyViewController.surveyDelegate = self
    present(ssSurveyViewController, animated: true, completion: nil)
  }

  @IBAction func showEmbeddedSurvey(_ sender: UIButton) {
    ssSurveyView.loadEmbedSurvey(domain:"<account-domain>",token:"<sdk-token>", params:["emailaddress":"email@email.com","email":"email@email.com"])
  }

  @IBAction func startSurvey(_ sender: UIButton) {
    ssSurveyView.loadFullscreenSurvey(parent: self,delegate: self, domain:"<account-domain>",
    token:"<sdk-token>", params:["emailaddress":"email@email.com","email":"email@email.com"])
  }
  
  func handleSurveyResponse(response: [String : AnyObject]) {
    print(response)
  }

  func handleSurveyLoaded(response: [String : AnyObject]){
    print(response)
  }

  func handleSurveyValidation(response: [String : AnyObject]) {
    print(response)
  }
}

