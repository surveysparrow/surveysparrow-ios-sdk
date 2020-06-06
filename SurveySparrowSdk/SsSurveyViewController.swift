//
//  SsSurveyViewController.swift
//  SurveySparrowSdk
//
//  Created by Ajay Sivan on 05/06/20.
//  Copyright © 2020 SurveySparrow. All rights reserved.
//

import UIKit

@IBDesignable
public class SsSurveyViewController: UIViewController, SsSurveyDelegate {
  // MARK: Properties
  var surveyDelegate: SsSurveyDelegate!
  
  var params: [String: String] = [:]
  
  @IBInspectable var domain: String?
  @IBInspectable var token: String?
  @IBInspectable var thankyouTimeout: Double = 3.0

  // MARK: Initialize
  public override func viewDidLoad() {
    super.viewDidLoad()
    
    view.backgroundColor = view.backgroundColor == nil ? .white : view.backgroundColor
    if domain != nil && token != nil {
      let ssSurveyView = SsSurveyView()
      ssSurveyView.surveyDelegate = self
      ssSurveyView.params = params
      
      ssSurveyView.frame = view.bounds
      ssSurveyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      
      ssSurveyView.loadSurvey(domain: domain, token: token)
      view.addSubview(ssSurveyView)
    } else {
      print("Error: Domain or token is nil")
    }
  }
  
  // MARK: Delegate
  public func handleSurveyResponse(response: [String : Any]) {
    if surveyDelegate != nil {
      surveyDelegate.handleSurveyResponse(response: response)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + thankyouTimeout) {
      self.dismiss(animated: true, completion: nil)
    }
  }
}
