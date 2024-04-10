//
//  File.swift
//  
//
//  Created by Gokulkrishna raju on 03/04/24.
//

import SwiftUI
import WebKit

@available(iOS 14.0, *)
public struct WebView: View {
    
    let urlString: String
    @State private var isLoading: Bool = true

    public var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            WebViewRepresentable(urlString: urlString, isLoading: $isLoading)
        }
    }
}

@available(iOS 14.0, *)
struct WebViewRepresentable: UIViewRepresentable {
    let urlString: String
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
    }
}
