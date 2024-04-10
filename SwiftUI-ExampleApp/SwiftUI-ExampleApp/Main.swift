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
var spotCheck = Spotcheck(email: "gokulkrishna.raju@surveysparrow.com", firstName: "gokulkrishna", lastName: "raju", phoneNumber: "6383846825")
// domain, target token

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
