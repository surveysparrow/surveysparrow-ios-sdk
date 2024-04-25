//
//  ContentView.swift
//  ExampleApp
//
//  Created by Gokulkrishna Raju on 05/01/24.
//

import SwiftUI
import SurveySparrowSdk

 
@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
 
struct ContentView: View {
    
    @State private var isModalPresented : Bool = false
    @State private var showEmbedSurvey : Bool = false
    @State private var isValidationPresented : Bool = false
    
    var domain: String = "gokulkrishnaraju1183.surveysparrow.com"
    var token: String = "tt-v1anVo2KsJuoLnpMvC29dX"
    
    var body: some View {
        VStack {
            Button{
                isModalPresented = true
            } label:{
                Text("Show Full Screen Survey")
            }.padding().padding(.top,60)
            Button{
                FullScreenSurveyWithValidation(domain: domain, token: token).startFullScreenSurveyWithValidation()
            } label:{
                Text("Show Full Screen Survey with Validation")
            }.padding()
            Button{
                showEmbedSurvey.toggle()
            }label: {
                Text("Show Embed Survey")
            }
            Spacer()
            EmbeddedSurveyView(isSurveyActive: $showEmbedSurvey, domain: domain, token: token)
                .frame(height: 400)
        }.sheet(isPresented: $isModalPresented) {
            FullScreenSurveyView(domain: domain, token: token)
        }
    }
}
