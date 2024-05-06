//
//  SpotCheckScreen.swift
//  SwiftUI-ExampleApp
//
//  Created by Gokulkrishna raju on 01/03/24.
//

import SwiftUI

@available(iOS 15.0, *)
struct SpotCheckScreen: View {
    var body: some View {
        VStack {
            Text("SpotCheckScreen")
                .padding()
            Button(
                action: {
                    spotCheck.TrackEvent(onScreen: "SpotCheckScreen", event: [ "MobileClick": [] ])
                }
            ){
                Text("Click")
            }
            .padding()
        }
        .onAppear {
            spotCheck.TrackScreen(screen: "SpotCheckScreen")
        }
    }
}

@available(iOS 15.0, *)
struct SpotCheckScreen2: View {
    var body: some View {
        VStack {
            Text("SpotCheckScreen2")
                .padding()
            Button(
                action: {
                    spotCheck.TrackEvent(onScreen: "SpotCheckScreen2", event: [ "MobileClick": [] ])
                }
            ){
                Text("Click")
            }
            .padding()
        }
        .onAppear {
            spotCheck.TrackScreen(screen: "SpotCheckScreen2")
        }
    }
}

//ButtonClick
