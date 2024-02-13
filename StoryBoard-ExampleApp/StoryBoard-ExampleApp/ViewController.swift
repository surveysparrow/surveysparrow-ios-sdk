//
//  ViewController.swift
//  StoryBoard-ExampleApp
//
//  Created by Gokulkrishna raju on 31/01/24.
//

import UIKit
import SurveySparrowSdk

class ViewController: UIViewController, SsSurveyDelegate {

    var domain: String = "mobile-sdk.surveysparrow.com"
    var token: String = "ntt-aMYx9J89WmrV46pvbGEJNz"
    
    @IBOutlet weak var ssSurveyView: SsSurveyView!
   
    @IBAction func showFullScreenSurvey(_ sender: UIButton) {
        let ssSurveyViewController = SsSurveyViewController()
        ssSurveyViewController.domain = domain
        ssSurveyViewController.token = token
        ssSurveyViewController.params = ["emailaddress":"email@email.com","email":"email@email.com"]
        ssSurveyViewController.getSurveyLoadedResponse = true
        ssSurveyViewController.surveyDelegate = self
        present(ssSurveyViewController, animated: true, completion: nil)    }
    
    @IBAction func startSurvey(_ sender: UIButton) {
        ssSurveyView.loadFullscreenSurvey(parent: self,delegate: self, domain:domain,
        token:token, params:["emailaddress":"email@email.com","email":"email@email.com"])
    }
    
    @IBAction func showEmbedSurvey(_ sender: UIButton) {
        ssSurveyView.loadEmbedSurvey(domain:domain,token:token, params:["emailaddress":"email@email.com","email":"email@email.com"])
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
