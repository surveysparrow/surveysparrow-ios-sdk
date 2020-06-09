//
//  SurveySparrow.swift
//  SurveySparrowSdk
//
//  Created by Ajay Sivan on 06/06/20.
//  Copyright © 2020 SurveySparrow. All rights reserved.
//

import Foundation
import UIKit

public class SurveySparrow {
  // MARK: Properties
  private var dataStore = NSUbiquitousKeyValueStore()
  private var domain: String
  private var token: String
  
  public var params: [String: String]?
  public var thankyouTimout: Double = 3.0
  public var surveyDelgate: SsSurveyDelegate!
  public var alertTitle: String = "Rate us"
  public var alertMessage: String = "Share your feedback and let us know how we are doing"
  public var alertPositiveButton: String = "Rate Now"
  public var alertNegativeButton: String = "Later"
  public var isConnectedToNetwork: Bool = true
  public var startAfter: Int = 3
  public var repeatInterval: Int = 5
  public var incrementalRepeat: Bool = false
  public var repeatSurvey: Bool = false
  
  private var isAlreadyTakenKey = "isAlreadyTaken_"
  private var promptTimeKey = "promptTime_"
  private var incrementMultiplierKey = "incrementMultiplier_"
  
  // MARK: Initialization
  public init(domain: String, token: String) {
    self.domain = domain
    self.token = token
    
    isAlreadyTakenKey += token
    promptTimeKey += token
    incrementMultiplierKey += token
  }
  
  // MARK: Public methods
  public func scheduleSurvey(parent: UIViewController) {
    let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
    let isAlreadyTaken = UserDefaults.standard.bool(forKey: isAlreadyTakenKey)
    let promptTime = UserDefaults.standard.integer(forKey: promptTimeKey)
    var incrementMultiplier = UserDefaults.standard.integer(forKey: incrementMultiplierKey)
    incrementMultiplier = incrementMultiplier == 0 ? 1 : incrementMultiplier
    
    if promptTime == 0 {
      let nextPrompt = currentTime + Int64(startAfter * 24 * 60 * 60 * 1000)
      UserDefaults.standard.set(nextPrompt, forKey: promptTimeKey)
      dataStore.set(1, forKey: incrementMultiplierKey)
      return
    }
    
    if isConnectedToNetwork && (!isAlreadyTaken || repeatSurvey) && (promptTime < currentTime) {
      let alertDialog = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: UIAlertController.Style.alert)
      alertDialog.addAction(UIAlertAction(title: alertPositiveButton, style: UIAlertAction.Style.default, handler: {action in
        let ssSurveyViewController = SsSurveyViewController()
        ssSurveyViewController.domain = self.domain
        ssSurveyViewController.token = self.token
        ssSurveyViewController.thankyouTimeout = self.thankyouTimout
        ssSurveyViewController.surveyDelegate = self.surveyDelgate
        parent.present(ssSurveyViewController, animated: true, completion: nil)
      }))
      alertDialog.addAction(UIAlertAction(title: alertNegativeButton, style: UIAlertAction.Style.cancel, handler: nil))
      parent.present(alertDialog, animated: true)
      
      UserDefaults.standard.set(incrementalRepeat ? incrementMultiplier * 2 : 1, forKey: self.incrementMultiplierKey)
      UserDefaults.standard.set(true, forKey: isAlreadyTakenKey)
      let timeTillNext = Int64(repeatInterval * 24 * 60 * 60 * 1000 * incrementMultiplier)
      let nextPrompt = currentTime + timeTillNext
      UserDefaults.standard.set(nextPrompt, forKey: promptTimeKey)
    }
  }
  
  public func clearSchedule() {
    UserDefaults.standard.removeObject(forKey: incrementMultiplierKey)
    UserDefaults.standard.removeObject(forKey: isAlreadyTakenKey)
    UserDefaults.standard.removeObject(forKey: promptTimeKey)
  }
}