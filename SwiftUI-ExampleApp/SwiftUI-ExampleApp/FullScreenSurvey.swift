//
//  FullScreenSurvey.swift
//  Example
//
//  Created by Gokulkrishna Raju on 26/12/23.
//

import SwiftUI
import SurveySparrowSdk

class SurveyDelegate: SsSurveyDelegate {
    func handleCloseButtonTap() {
        print("CloseButtonTap")
    }
    
    func handleSurveyResponse(response: [String: AnyObject]) {
        print("Survey Response: \(response)")
    }

    func handleSurveyLoaded(response: [String: AnyObject]) {
        print("Survey Loaded: \(response)")
    }

    func handleSurveyValidation(response: [String: AnyObject]) {
        print("Survey Validation: \(response)")
    }
}

struct FullScreenSurveyView: UIViewControllerRepresentable {
    
    var domain: String
    var token: String
    let sparrowLang: String
    let params: [String: String]
    
    @State private var isSurveyLoaded: Bool = false

    func makeUIViewController(context: Context) -> SsSurveyViewController{
        let ssSurveyViewController = SsSurveyViewController()
        ssSurveyViewController.domain = domain
        ssSurveyViewController.token = token
        ssSurveyViewController.sparrowLang = sparrowLang
        ssSurveyViewController.params = params
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
    let sparrowLang: String?
    let params: [String: String]?

    func startFullScreenSurveyWithValidation() {
           if let parentViewController = UIApplication.shared.windows.first?.rootViewController {
               print("Success")
               SsSurveyView().loadFullscreenSurvey(parent: parentViewController, delegate: SurveyDelegate(), domain: domain, token: token, params: params, sparrowLang: sparrowLang)
           } else {
               print("Error: Unable to access parentViewController.")
           }
       }
}
