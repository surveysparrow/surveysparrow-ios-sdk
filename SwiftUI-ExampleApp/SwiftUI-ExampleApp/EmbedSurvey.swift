//
//  EmbededSurvey.swift
//  Example
//
//  Created by Gokulkrishna Raju on 16/01/24.
//


import SwiftUI
import SurveySparrowSdk


struct EmbeddedSurveyView: UIViewControllerRepresentable {
    @Binding var isSurveyActive: Bool
    var domain: String
    var token: String
    let params: [String: String]
    let properties: [String: Any]
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {        
        if isSurveyActive {
            let surveyView = SsSurveyView(properties: properties)
            surveyView.surveyDelegate = SurveyDelegate()
            surveyView.loadEmbedSurvey(domain: domain, token: token, params: params)
            uiViewController.view.addSubview(surveyView)
            surveyView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                surveyView.topAnchor.constraint(equalTo: uiViewController.view.topAnchor),
                surveyView.bottomAnchor.constraint(equalTo: uiViewController.view.bottomAnchor),
                surveyView.leadingAnchor.constraint(equalTo: uiViewController.view.leadingAnchor),
                surveyView.trailingAnchor.constraint(equalTo: uiViewController.view.trailingAnchor)
            ])
            
            DispatchQueue.main.async {
                self.isSurveyActive = false
            }
        }
    }
}
