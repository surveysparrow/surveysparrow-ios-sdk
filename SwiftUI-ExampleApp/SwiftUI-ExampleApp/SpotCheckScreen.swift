//
//  SpotCheckScreen.swift
//  SwiftUI-ExampleApp
//
//  Created by Gokulkrishna raju on 01/03/24.
//

import SwiftUI

@available(iOS 15.0, *)
struct HomeScreen: View {
    var body: some View {
        VStack {
            Text("HomeScreen")
                .padding()
            Button(
                action: {
                    spotCheck.TrackEvent(onScreen: "HomeScreen", event: [ "SendPost": ["postSentTime": "5.30pm"] ])
                }
            ){
                Text("Click")
            }
            .padding()
        }
        .onAppear {
            spotCheck.TrackScreen(screen: "HomeScreen")
        }
    }
}

@available(iOS 15.0, *)
struct NetworkScreen: View {
    var body: some View {
        VStack {
            Text("NetworkScreen")
                .padding()
            Button(
                action: {
                    spotCheck.TrackEvent(onScreen: "NetworkScreen", event: [ "MobileClick": ["abc": "bbb"] ])
                }
            ){
                Text("Click")
            }
            .padding()
        }
        .onAppear {
            spotCheck.TrackScreen(screen: "NetworkScreen")
        }
    }
}

//ButtonClick
