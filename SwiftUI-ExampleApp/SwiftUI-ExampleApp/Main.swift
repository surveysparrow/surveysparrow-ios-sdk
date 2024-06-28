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
    
    var domain: String = "<account-domain>"
    var token: String = "<sdk-token>"
    var sparrowLang: String = "<your-preferred-language-code>"
    var params: [String:String] = ["emailaddress": "email@email.com", "email": "email@email.com"]
    
    var body: some View {
        VStack {
            Button{
                isModalPresented = true
            } label:{
                Text("Show Full Screen Survey")
            }.padding().padding(.top,60)
            Button{
                FullScreenSurveyWithValidation(domain: domain, token: token, sparrowLang: sparrowLang, params: params).startFullScreenSurveyWithValidation()
            } label:{
                Text("Show Full Screen Survey with Validation")
            }.padding()
            Button{
                showEmbedSurvey.toggle()
            }label: {
                Text("Show Embed Survey")
            }
            Spacer()
            EmbeddedSurveyView(isSurveyActive: $showEmbedSurvey, domain: domain, token: token, sparrowLang: sparrowLang, params: params)
                .frame(height: 400)
        }.sheet(isPresented: $isModalPresented) {
            FullScreenSurveyView(domain: domain, token: token, sparrowLang: sparrowLang, params: params)
        }
    }
}
