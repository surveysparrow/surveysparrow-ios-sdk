//
//  ContentView.swift
//  ExampleApp
//
//  Created by Gokulkrishna Raju on 05/01/24.
//

import SwiftUI
import SurveySparrowSdk

 
@main
@available(iOS 15.0, *)
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@available(iOS 15.0, *)
struct ContentView: View {
    
    @State private var isModalPresented : Bool = false
    @State private var showEmbedSurvey : Bool = false
    @State private var isValidationPresented : Bool = false
    
    @State private var domain: String = "<account-domain>"
    @State private var token: String = "<sdk-token>"
    @State private var sparrowLang: String = "<your-preferred-language-code>"
    var params: [String:String] = ["emailaddress": "email@email.com", "email": "email@email.com"]
    
    var body: some View {
        ScrollView {
            CustomTextField(
                placeholder: "Domain",
                text: $domain
            )
            
            CustomTextField(
                placeholder: "Token",
                text: $token
            )
            
            CustomTextField(
                placeholder: "SparrowLang",
                text: $sparrowLang
            )
            
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
            
            Button {
                showEmbedSurvey = true
            } label: {
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


@available(iOS 15.0, *)
struct CustomTextField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .padding(.vertical, 10)
            .overlay(
                VStack {
                    Spacer()
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.secondary)
                }
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.horizontal)
    }
}
