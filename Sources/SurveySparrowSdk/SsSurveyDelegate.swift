//
//  SsSurveyDelegate.swift
//  SurveySparrowSdk
//
//  Created by Gokulkrishna raju on 09/02/24.
//  Copyright © 2020 SurveySparrow. All rights reserved.
//

import Foundation

public protocol SsSurveyDelegate {
    func handleSurveyResponse(response: [String: AnyObject])
    func handleSurveyLoaded(response: [String: AnyObject])
    func handleSurveyValidation(response: [String: AnyObject])
    func handleCloseButtonTap()
}
