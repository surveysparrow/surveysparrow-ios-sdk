//
//  EmbededSurvey.swift
//  Example
//
//  Created by Gokulkrishna Raju on 16/01/24.
//


import SwiftUI
import SurveySparrowSdk

struct EmbeddedSurveyView: UIViewRepresentable {
    @Binding var isSurveyActive: Bool
    var domain: String
    var token: String
    let surveyView = SsSurveyView()

    func makeUIView(context: Context) -> UIView {
        return surveyView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if isSurveyActive {
            surveyView.surveyDelegate = SurveyDelegate()
            surveyView.loadEmbedSurvey(domain: domain, token: token , params: ["emailaddress": "email@email.com", "email": "email@email.com"])
            DispatchQueue.main.async {
                self.isSurveyActive = false
            }
        }
    }
}
