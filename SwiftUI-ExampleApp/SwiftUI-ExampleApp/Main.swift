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
    email: "gokulkrishna.raju@surveysparrow.com",
    domainName: "rgk.ap.ngrok.io",
    targetToken: "tar-qeaHP85gPG21ZBotb758a7",
    firstName: "gokulkrishna",
    lastName: "raju", 
    phoneNumber: "6383846825",
    location: [
        "latitude": 12.947021473352041,
        "longitude": 80.23236112554345
    ]
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
    
    var domain: String = "rgk.marketsparrow.com"
    var token: String = "ntt-pgeMhemppcfxmBoPK6fBzd"
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollView {
                    NavigationLink(destination: SpotCheckScreen()) {
                        Text("SpotCheck")
                    }.padding().padding(.top,60)
                    NavigationLink(destination: SpotCheckScreen2()) {
                        Text("SpotCheck")
                    }
                    Button{
                        isModalPresented = true
                    } label:{
                        Text("Show Full Screen Survey")
                    }.padding()
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
            spotCheck
        }
    }
}

//@available(iOS 15.0, *)
//#Preview{
//    ContentView()
//}
