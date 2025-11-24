//
//  ContentView.swift
//  ExampleApp
//
//  Created by Gokulkrishna Raju on 05/01/24.
//


import SwiftUI
import CoreLocation
import SurveySparrowSdk

@available(iOS 15.0, *)


var spotCheck = Spotcheck(
    domainName: "",
    targetToken: "",
    userDetails: [:],
    sparrowLang: "",
    surveyDelegate: SsDelegate()
)

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
    @State private var scrollOffset: CGFloat = 0
    
    @State private var domain: String = "<account-domain>"
    @State private var token: String = "<sdk-token>"
    let properties: [String: Any] = [
        "sparrowLang": "",
        "isCloseButtonEnabled" : true
    ]
    
    var params: [String:String] = ["emailaddress": "email@email.com", "email": "email@email.com"]
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    NavigationLink(destination: HomeScreen()) {
                        Text("HomeScreen")
                    }.padding().padding(.top,60)
                    NavigationLink(destination: NetworkScreen()) {
                        Text("NetworkScreen")
                    }
                    Button{
                        isModalPresented = true
                    } label:{
                        Text("Show Full Screen Survey")
                    }.padding()
                    Button{
                        FullScreenSurveyWithValidation(domain: domain, token: token, properties: properties, params: params).startFullScreenSurveyWithValidation()
                    } label:{
                        Text("Show Full Screen Survey with Validation")
                    }.padding()
                    Button{
                        showEmbedSurvey.toggle()
                    }label: {
                        Text("Show Embed Survey")
                    }
                    Spacer()
                    EmbeddedSurveyView(isSurveyActive: $showEmbedSurvey, domain: domain, token: token, params: params, properties: properties)
                        .frame(height: 400)
                }.sheet(isPresented: $isModalPresented) {
                    FullScreenSurveyView(domain: domain, token: token, params: params, properties: properties)
                }.background(spotCheck.navControllerFinder)
            }
            spotCheck
        }
    }
}

//@available(iOS 15.0, *)
//#Preview{
//    ContentView()
//}

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

@available(iOS 15.0, *)
class SsDelegate: UIViewController, SsSpotcheckDelegate {

    func handleSurveyResponse(response: [String : AnyObject]) async {
        print("Received survey response: ", response)
    }

    func handlePartialSubmission(response: [String : AnyObject]) async {
        print("Received partial Submission: ", response)
    }

    func handleSurveyLoaded(response: [String : AnyObject]) async {
        print("Survey Loaded: ", response)
    }

    func handleCloseButtonTap() async {
        print("Survey closed by the User.")
    }
}

