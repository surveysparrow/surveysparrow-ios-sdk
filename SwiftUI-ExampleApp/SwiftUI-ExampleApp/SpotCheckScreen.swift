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
        ZStack{
            VStack {
                Text("HomeScreen")
                    .padding()
                Button(
                    action: {
                        spotCheck.TrackEvent(onScreen: "HomeScreen", event: [ "onEvent": [] ])
                    }
                ){
                    Text("Click")
                }
                .padding()
                NavigationLink(destination: NetworkScreen()) {
                    Text("NetworkScreen")
                }
                .padding()
            }
            spotCheck
        }
        .onAppear {
            print("HomeScreen")
            spotCheck.TrackScreen(screen: "HomeScreen")
        }
    }
}

@available(iOS 15.0, *)
struct NetworkScreen: View {
    var body: some View {
        ZStack{
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
            spotCheck
        }
        .onAppear {
            print("NetworkScreen")
            spotCheck.TrackScreen(screen: "NetworkScreen")
        }
    }
}

//ButtonClick
