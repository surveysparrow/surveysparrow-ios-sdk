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
                 variables: [String: Any] = [:],
                 customProperties: [String: Any] = [:]
    ) {
        self.state = SpotcheckState(
            email: email,
            targetToken: targetToken,
            domainName: domainName,
            firstName: firstName,
            lastName: lastName,
            phoneNumber: phoneNumber,
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
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
                
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
