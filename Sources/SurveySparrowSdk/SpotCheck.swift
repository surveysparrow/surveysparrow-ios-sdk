import SwiftUI

@available(iOS 15.0, *)
public struct Spotcheck: View {
    
    @ObservedObject var state: SpotcheckState
    
    public init( email: String,
                 domainName:String,
                 targetToken: String,
                 firstName: String = "",
                 lastName: String = "",
                 phoneNumber: String = "",
                 location: [String: Double] = [:]
    ) {
        self.state = SpotcheckState(
            email: email,
            targetToken: targetToken,
            domainName: domainName,
            firstName: firstName,
            lastName: lastName,
            phoneNumber: phoneNumber,
            location: location
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + state.afterDelay + 1) {
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
                DispatchQueue.main.asyncAfter(deadline: .now() + state.afterDelay + 1) {
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
                                pressedColor: state.closeButtonStyle["backgroundColor"] ?? "#000000",
                                iconColor: state.closeButtonStyle["ctaButton"] ?? "#000000"
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
    var pressedColor: String
    var iconColor: String
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .padding(24) 
            .foregroundColor(Color(hex: iconColor))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color(hex: pressedColor) : Color.black.opacity(0) )
            )
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.1))
    }
}

@available(iOS 13.0, *)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
