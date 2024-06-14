import SwiftUI

@available(iOS 15.0, *)
public struct Spotcheck: View {
    
    @ObservedObject var state: SpotcheckState
    
    public init(
                 domainName:String,
                 targetToken: String,
                 userDetails: [String: Any] = [:],
                 variables: [String: Any] = [:],
                 customProperties: [String: Any] = [:]
    ) {
        self.state = SpotcheckState(
            targetToken: targetToken,
            domainName: domainName,
            userDetails: userDetails,
            variables: variables,
            customProperties: customProperties
        )
    }
    
    public func TrackScreen(screen: String) {
        state.sendTrackScreenRequest(screen: screen) { valid, multiShow in
            if multiShow {
                if valid {
                    print("MultiShow Passed")
                } else {
                    print("TrackScreen Failed")
                }
            } else {
                if valid {
                    DispatchQueue.main.asyncAfter(deadline: .now() + state.afterDelay) {
                        state.start()
                        print("TrackScreen Passed")
                    }
                } else {
                    print("TrackScreen Failed")
                }
            }
            
        }
    }
    
    public func TrackEvent(onScreen screen: String, event: [String: Any]) {
        state.sendTrackEventRequest(screen: screen, event: event) { valid in
            if valid {
                DispatchQueue.main.asyncAfter(deadline: .now() + state.afterDelay) {
                    state.start()
                    print("TrackEvent Passed")
                }
            } else {
                print("TrackEvent Failed")
            }
        }
    }
    
    public var body: some View {
        if  state.isVisible {
            ZStack {
                if state.currentQuestionHeight != 0 {
                    Spacer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                }
                VStack(){
                    if state.position == "bottom" {
                        Spacer()
                    }
                    WebViewContainer(state: state)
                        .frame(
                            height:
                                self.state.isFullScreenMode
                            ? (UIScreen.main.bounds.height - 100)
                            : min(
                                (UIScreen.main.bounds.height - 100),
                                (
                                    min(
                                        state.currentQuestionHeight,
                                        (state.maxHeight * UIScreen.main.bounds.height)
                                    )
                                    +
                                    (state.isBannerImageOn && state.currentQuestionHeight != 0  ? 100 : 0)
                                )
                            )
                        )
                    if state.position == "top" {
                        Spacer()
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
}

@available(iOS 15.0, *)
struct WebViewContainer: View, SsSurveyDelegate {
    var state: SpotcheckState
    
    init(state: SpotcheckState) {
        self.state = state
    }
    
    var body: some View {
        GeometryReader { geometry in
            WebView(delegate: self, state: state)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .fixedSize(horizontal: true, vertical: false)
                .clipShape(RoundedRectangle(cornerRadius: 0))
                .shadow(radius: 20)
                .overlay(alignment: .topTrailing) {
                    if(state.isCloseButtonEnabled && (self.state.isFullScreenMode || state.currentQuestionHeight != 0)){
                        Button {
                            state.closeSpotCheck()
                            state.spotcheckID = 0
                            state.position = ""
                            state.currentQuestionHeight = 0
                            state.isCloseButtonEnabled = false
                            state.closeButtonStyle = [:]
                            state.spotcheckContactID = 0
                            state.spotcheckURL = ""
                            state.end()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(
                            CustomButtonStyle(
                                iconColor: (
                                    state.closeButtonStyle["ctaButton"] != nil
                                    && state.closeButtonStyle["ctaButton"]!.isNotHex()
                                ) ? "#000000" : state.closeButtonStyle["ctaButton"] ?? "#000000"
                            )
                        )
                    }
                }
        }
    }
    
    public func handleCloseButtonTap() {
        print("CloseButton Tapped")
    }
    
    public func handleSurveyResponse(response: [String : AnyObject]) {
        print("Submit Response",response)
    }
    
    public func handleSurveyLoaded(response: [String : AnyObject]) {
        print("Survey Loaded", response)
    }
    
    public func handleSurveyValidation(response: [String : AnyObject]) {
        print(response)
    }
}

@available(iOS 13.4, *)
struct CustomButtonStyle: ButtonStyle {
    var iconColor: String

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .padding(24)
            .foregroundColor(Color(hex: iconColor))
            .contentShape(Rectangle())
    }
}

@available(iOS 13.0, *)
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        scanner.currentIndex = hex.hasPrefix("#") ? hex.index(after: hex.startIndex) : hex.startIndex
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension String {
    func isNotHex() -> Bool {
        let hexPattern = "^#(?:[0-9a-fA-F]{3}){1,2}$"
        let regex = try? NSRegularExpression(pattern: hexPattern, options: .caseInsensitive)
        let matches = regex?.matches(in: self, options: [], range: NSRange(location: 0, length: self.count))
        return matches?.count == 0
    }
}
