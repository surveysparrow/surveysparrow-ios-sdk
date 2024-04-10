import SwiftUI

@available(iOS 15.0, *)
public struct Spotcheck: View {
    
    var email: String
    var firstName: String
    var lastName: String
    var phoneNumber: String

    @ObservedObject var state: SpotcheckState

    public init(email: String , firstName: String = "", lastName: String = "", phoneNumber: String = "") {
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.state = SpotcheckState(email: email, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber)
    }
    
    public func TrackScreen(_ screen: String) {
        state.sendRequest(screen: screen, event: nil) { valid in
            if valid {
                state.start()
            } else {
                print("Invalid")
            }
        }
    }
    
    public func TrackEvent(_ event: String) {
        state.sendRequest(screen: nil, event: event) { valid in
            if valid {
                state.start()
            } else {
                print("Invalid")
            }
        }
    }

    public var body: some View {
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
                    Button {
                        state.end()
                    } label: {
                        Image(systemName: "xmark").font(.title2)
                    }
                    .tint(Color.black)
                    .padding()
                }
            if state.position == "top" {
                Spacer()
            }
        }
        .gesture(
            DragGesture().onChanged { val in
                
                print(val)
            }
        )
        .edgesIgnoringSafeArea(.bottom)
        .background(Color.gray.opacity(0.0001))
        .offset(x: 0, y: state.offset)
    }
}
