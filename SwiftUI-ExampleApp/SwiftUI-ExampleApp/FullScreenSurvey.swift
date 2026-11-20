//
//  FullScreenSurvey.swift
//  Example
//
//  Created by Gokulkrishna Raju on 26/12/23.
//

import SwiftUI
import SurveySparrowSdk

class SurveyDelegate: SsSurveyDelegate {
    func handleCloseButtonTap() {}

    func handleSurveyResponse(response: [String: AnyObject]) {}

    func handleSurveyLoaded(response: [String: AnyObject]) {}

    func handleSurveyValidation(response: [String: AnyObject]) {}
}

struct FullScreenSurveyView: UIViewControllerRepresentable {
    
    var domain: String
    var token: String
    let params: [String: String]
    let properties: [String: Any]
    
    @State private var isSurveyLoaded: Bool = false

    func makeUIViewController(context: Context) -> SsSurveyViewController{
        let ssSurveyViewController = SsSurveyViewController()
        ssSurveyViewController.domain = domain
        ssSurveyViewController.token = token
        ssSurveyViewController.params = params
        ssSurveyViewController.properties = properties
        ssSurveyViewController.getSurveyLoadedResponse = true
        ssSurveyViewController.surveyDelegate = SurveyDelegate()
        return ssSurveyViewController
    }

    func updateUIViewController(_ uiViewController: SsSurveyViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
}

struct FullScreenSurveyWithValidation {
    
    let domain: String?
    let token: String?
    let properties: [String: Any]
    let params: [String: String]?

    func startFullScreenSurveyWithValidation() {
           if let parentViewController = UIApplication.shared.windows.first?.rootViewController {
               SsSurveyView(properties: properties).loadFullscreenSurvey(parent: parentViewController, delegate: SurveyDelegate(), domain: domain, token: token, params: params)
           }
       }
}
