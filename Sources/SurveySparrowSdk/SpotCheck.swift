import SwiftUI

@available(iOS 15.0, *)
public struct Spotcheck: View {
    
    @ObservedObject var state: SpotcheckState
    
    public init(email: String, domainName:String, targetToken: String, firstName: String = "", lastName: String = "", phoneNumber: String = "", location: [String: Double] = [:]) {
        self.state = SpotcheckState(email: email, targetToken: targetToken, domainName: domainName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber, location: location)
    }
    
    public func TrackScreen(_ screen: String) {
        state.sendRequest(screen: screen, event: nil) { valid, multiShow in
            if valid && !multiShow {
                DispatchQueue.main.asyncAfter(deadline: .now() + state.afterDelay) {
                    state.start()
                }
            } else {
                print("TrackScreen Failed")
            }
        }
    }
    
    public func TrackEvent(_ event: String) {
        state.sendRequest(screen: nil, event: event) { valid, multiShow in
            if valid && !multiShow {
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
            Color.black.opacity(0.1)
            VStack{
                if state.position == "bottom" {
                    Spacer()
                }
                WebView(urlString: state.spotcheckURL)
                    .frame(width: UIScreen.main.bounds.width, height: 360)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .shadow(radius: 20)
                    .overlay(alignment: .topTrailing) {
                        if(state.isCloseButtonEnabled){
                            Button {
                                state.closeSpotCheck()
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
        }
        .offset(x: 0, y: state.offset)
    }
}
