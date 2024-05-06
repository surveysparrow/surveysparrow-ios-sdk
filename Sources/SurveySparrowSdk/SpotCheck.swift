import SwiftUI

@available(iOS 15.0, *)
public struct Spotcheck: View, SsSurveyDelegate {
    
    @ObservedObject var state: SpotcheckState
    
    public init(email: String, domainName:String, targetToken: String, firstName: String = "", lastName: String = "", phoneNumber: String = "", location: [String: Double] = [:]) {
        self.state = SpotcheckState(email: email, targetToken: targetToken, domainName: domainName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber, location: location)
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
                    }
                } else {
                    print("TrackEvent Failed")
                }
            }
    }
    
    public var body: some View {
        
        ZStack{
            if  state.offset == 0 {
                Color.black.opacity(0.1)
                VStack{
                    if state.position == "bottom" {
                        Spacer()
                    }
                    WebView(urlString: state.spotcheckURL, delegate: self, state: state)
                        .frame(width: UIScreen.main.bounds.width, height: max( UIScreen.main.bounds.height * state.maxHeight, 360))
                        .fixedSize(horizontal: false, vertical: true)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                        .shadow(radius: 20)
                        .overlay(alignment: .topTrailing) {
                            if(state.isCloseButtonEnabled){
                                Button {
                                    state.closeSpotCheck()
                                    state.spotcheckID = 0
                                    state.spotcheckContactID = 0
                                    state.spotcheckURL = ""
                                    state.end()
                                } label: {
                                    Image(systemName: "xmark").font(.title2)
                                }
                                .tint(Color.black)
                                .padding()
                            }
                        }
                    if state.position == "top" {
                        Spacer()
                    }
                    
                }
                .edgesIgnoringSafeArea(.bottom)
            } else {
                EmptyView()
            }
        }
        .offset(x: 0, y: state.offset)
        
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
