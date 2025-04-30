import SwiftUI

@available(iOS 15.0, *)
public struct Spotcheck: View {
    
    @ObservedObject var state: SpotcheckState
    
    public init(
                 domainName:String,
                 targetToken: String,
                 userDetails: [String: Any] = [:],
                 variables: [String: Any] = [:],
                 customProperties: [String: Any] = [:],
                 sparrowLang: String = "",
                 surveyDelegate: SsSurveyDelegate = ssSurveyDelegate()
    ) {
        self.state = SpotcheckState(
            targetToken: targetToken,
            domainName: domainName,
            userDetails: userDetails,
            variables: variables,
            customProperties: customProperties,
            sparrowLang: sparrowLang,
            surveyDelegate: surveyDelegate
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
                        print("TrackScreen Passed. Delay: \(state.afterDelay) Seconds")
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
                    print("TrackEvent Passed. Delay: \(state.afterDelay) Seconds")
                }
            } else {
                print("TrackEvent Failed")
            }
        }
    }
    
    public var body: some View {
        
        if (!state.classicUrl.isEmpty)
        {
            ZStack {
             
                    Spacer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.4))
                
                VStack(){
                    if state.spotcheckPosition == "bottom" {
                        Spacer()
                    }
                    VStack{
                        
                        if state.spotChecksMode == "miniCard" && state.isCloseButtonEnabled {
                            HStack {
                                Spacer()
                                
                                Button(action: {
                                    state.end()
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 32, height: 32)
                                            .shadow(color: Color.white.opacity(0.26), radius: 4, x: 0, y: 0)
                                        
                                        Image(systemName: "xmark")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                            .foregroundColor(.black)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        WebViewContainer(state: state, urlType: "classic")
                            .clipShape(RoundedRectangle(cornerRadius: (state.spotChecksMode == "miniCard") ? 12: 0))
                            .overlay(
                                RoundedRectangle(cornerRadius: (state.spotChecksMode == "miniCard") ? 12: 0)
                                    .stroke(Color.clear, lineWidth: (state.spotChecksMode == "miniCard") ? 2: 0)
                            )
                            .frame(
                                height: (!state.isVisible) ? 200 : self.state.isFullScreenMode
                                    ? (UIScreen.main.bounds.height - 100)
                                    : min(
                                        (UIScreen.main.bounds.height - 100),
                                        min(
                                            state.currentQuestionHeight,
                                            (state.maxHeight * UIScreen.main.bounds.height)
                                        )
                                    )
                            )
                        if state.spotChecksMode == "miniCard" && state.avatarEnabled && !state.avatarUrl.description.isEmpty {
                            HStack(alignment: .center) {
                                ImageView(url: state.avatarUrl)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(Color.white)
                                            .shadow(radius: 4)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
                                    .padding(.vertical, 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        
                    }.padding(.horizontal, (state.spotChecksMode == "miniCard") ? 8: 0)
                    if state.spotcheckPosition == "top" {
                        Spacer()
                    }
                }
                
            }.opacity((state.isVisible && state.spotCheckType=="classic" && !state.isClassicLoading && (state.isMounted || state.isFullScreenMode))  ? 1 : 0).disabled((state.isVisible && state.spotCheckType=="classic" && !state.isClassicLoading && (state.isMounted || state.isFullScreenMode)) ? false : true)
        }
        
        if (!state.chatUrl.isEmpty)
        {
            ZStack {
             
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background((state.isVisible && state.spotCheckType == "chat" && !state.isChatLoading)
                                ? Color.black.opacity(0.4)
                                : Color.clear)
                
                VStack(){
                    if state.spotcheckPosition == "bottom" {
                        Spacer()
                    }
                    WebViewContainer(state: state, urlType:"chat")
                        .frame(
                            height:(UIScreen.main.bounds.height - 100)
                        )
                    if state.spotcheckPosition == "top" {
                        Spacer()
                    }
                }
                
            }.opacity((state.isVisible && state.spotCheckType=="chat" && !state.isChatLoading && state.isFullScreenMode) ? 1 : 0).disabled((state.isVisible && state.spotCheckType=="chat" && !state.isChatLoading && state.isFullScreenMode) ? false : true)
        }

    }
}

@available(iOS 15.0, *)
struct ImageView: View {
    let url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .empty:
                EmptyView()
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Color.gray // fallback if image fails
            @unknown default:
                Color.gray
            }
        }
    }
}


@available(iOS 15.0, *)
struct WebViewContainer: View {
    @ObservedObject var state: SpotcheckState
    var urlType: String

    init(state: SpotcheckState, urlType: String) {
        self.state = state
        self.urlType = urlType

    }

    var body: some View {
        GeometryReader { geometry in
            WebView(delegate: state.surveyDelegate, state: state, urlType: self.urlType)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .fixedSize(horizontal: true, vertical: false)
                .clipShape(RoundedRectangle(cornerRadius: 0))
                .shadow(radius: 20)
                .overlay(alignment: .topTrailing) {
                    if (
                        self.state.isCloseButtonEnabled &&
                        (self.state.isFullScreenMode || self.state.currentQuestionHeight != 0) &&
                        self.state.spotChecksMode != "miniCard"
                    ) {
                        Button {
                            state.closeSpotCheck()
                            state.end()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(
                            CustomButtonStyle(
                                iconColor: (
                                    state.closeButtonStyle["ctaButton"] != nil &&
                                    state.closeButtonStyle["ctaButton"]!.isNotHex()
                                ) ? "#000000" : state.closeButtonStyle["ctaButton"] ?? "#000000"
                            )
                        )
                    }
                }
        }
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

@available(iOS 13.0, *)
struct Loader: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 6.0, lineCap: .round, lineJoin: .round))
                .opacity(0.3)
                .foregroundColor(Color.black)
            
            Circle()
                .trim(from: 0.0, to: 0.7)
                .stroke(lineWidth: 6.0)
                .foregroundColor(Color.white)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false))
                .onAppear {
                    self.isAnimating = true
                }
        }
        .frame(width: 60.0, height: 60.0)
    }
}

public class ssSurveyDelegate: SsSurveyDelegate {

    public init() {}

    public func handleSurveyResponse(response: [String : AnyObject]) {
        print("handleSurveyResponse", response)
    }

    public func handleSurveyLoaded(response: [String : AnyObject]) {
        print("handleSurveyLoaded", response)
    }

    public func handleSurveyValidation(response: [String : AnyObject]) {
        print("handleSurveyValidation", response)
    }

    public func handleCloseButtonTap() {
        print("CloseButtonTapped")
    }
}
