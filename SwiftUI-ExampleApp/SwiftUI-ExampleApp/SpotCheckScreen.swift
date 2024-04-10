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
        ZStack {
            Text("SpotCheckScreen")
        }
        .onAppear {
            spotCheck.TrackScreen("SpotCheckScreen")
        }
    }
}
