import SwiftUI
import WebKit

struct SpotCheckButtonConfig {
    var type: String = "floatingButton"
    var position: String = "bottom_right"
    var buttonSize: String = "medium"
    var backgroundColor: String = "#4A9CA6"
    var textColor: String = "#FFFFFF"
    var buttonText: String = ""
    var icon: String = ""
    var generatedIcon: String = ""
    var cornerRadius: String = "sharp"
    var onPress: () -> Void = {}
}

struct SpotCheckButtonUtils {
    static let FLOATING_BUTTON: [String: CGFloat] = [
        "small": 28, "medium": 32, "large": 40
    ]
    static let TEXT_BUTTON_ICON: [String: CGFloat] = [
        "small": 16, "medium": 20, "large": 24
    ]
    static let BORDER_RADIUS: [String: [String: CGFloat]] = [
        "sharp": ["small": 4, "medium": 6, "large": 8],
        "soft": ["small": 8, "medium":12, "large": 16],
        "smooth": ["small": 24, "medium": 16, "large": 24]
    ]
    
    static func getFloatingButtonSize(_ size: String) -> CGFloat {
        FLOATING_BUTTON[size] ?? FLOATING_BUTTON["medium"]!
    }
    
    static func getTextButtonIconSize(_ size: String) -> CGFloat {
        TEXT_BUTTON_ICON[size] ?? TEXT_BUTTON_ICON["medium"]!
    }
    
    static func getBorderRadius(_ corner: String, _ size: String) -> CGFloat {
        BORDER_RADIUS[corner]?[size] ?? 6
    }
    
    static func hexToColor(_ hex: String, opacity: Double = 1.0) -> Color {
        var hexClean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexClean.hasPrefix("#") { hexClean.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&rgb)
        let r, g, b: Double
        switch hexClean.count {
        case 3:
            r = Double((rgb >> 8) * 17) / 255.0
            g = Double(((rgb >> 4) & 0xF) * 17) / 255.0
            b = Double((rgb & 0xF) * 17) / 255.0
        case 6:
            r = Double((rgb >> 16) & 0xFF) / 255.0
            g = Double((rgb >> 8) & 0xFF) / 255.0
            b = Double(rgb & 0xFF) / 255.0
        default:
            return Color.black.opacity(opacity)
        }
        return Color(red: r, green: g, blue: b).opacity(opacity)
    }
    
    static func getTextStyle(for size: String) -> Font {
        switch size {
        case "small": return .system(size: 12, weight: .bold)
        case "large": return .system(size: 16, weight: .bold)
        default: return .system(size: 14, weight: .bold)
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}


struct InlineSVGView: UIViewRepresentable {
    var svgString: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        
        let htmlString = """
        <html>
          <head>
            <meta name='viewport' content='width=device-width, initial-scale=1.0'>
            <style>
              body { margin: 0; padding: 0; background: transparent; display: flex; justify-content: center; align-items: center; height: 100%; }
              svg { width: 100%; height: 100%; }
            </style>
          </head>
          <body>\(svgString)</body>
        </html>
        """
        webView.loadHTMLString(htmlString, baseURL: nil)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}


struct SpotCheckIcon: View {
    var icon: String
    var buttonSize: String
    var type: String = "textButton"
    
    private var size: CGFloat {
        type == "floatingButton"
        ? SpotCheckButtonUtils.getFloatingButtonSize(buttonSize) * 0.85
        : SpotCheckButtonUtils.getTextButtonIconSize(buttonSize)
    }
    
    var body: some View {
        Group {
            if icon.isEmpty {
                Color.clear
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if icon.trimmingCharacters(in: .whitespaces).contains("<svg") {
                
                InlineSVGView(svgString: icon)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .aspectRatio(contentMode: .fit)
            } else {
                if #available(iOS 15.0, *) {
                    AsyncImage(url: URL(string: icon)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure(_):
                            Image(systemName: "photo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .empty:
                            Color.clear
                        @unknown default:
                            Color.clear
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                } else {
                    Color.clear
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                }
            }
        }
        .frame(width: size, height: size)
    }
}



struct FloatingButton: View {
    var config: SpotCheckButtonConfig
    
    var body: some View {
        let size = SpotCheckButtonUtils.getFloatingButtonSize(config.buttonSize)
        let bgColor = SpotCheckButtonUtils.hexToColor(config.backgroundColor)
        let outer = size + 16
        let middle = size + 8
        
        VStack {
            Spacer()
            HStack {
                if config.position.contains("right") { Spacer(minLength: 0) }
                Button(action: config.onPress) {
                    ZStack {
                        Circle().fill(bgColor.opacity(0.25))
                            .frame(width: outer, height: outer)
                        Circle().fill(bgColor.opacity(0.5))
                            .frame(width: middle, height: middle)
                        Circle().fill(bgColor)
                            .frame(width: size, height: size)
                            .overlay(
                                SpotCheckIcon(
                                    icon: config.generatedIcon.isEmpty ? config.icon : config.generatedIcon,
                                    buttonSize: config.buttonSize,
                                    type: "floatingButton"
                                )
                            )
                            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                    }
                }
                if config.position.contains("left") { Spacer(minLength: 0) }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct TextButton: View {
    var config: SpotCheckButtonConfig
    
    var body: some View {
        let radius = SpotCheckButtonUtils.getBorderRadius(config.cornerRadius, config.buttonSize)
        let bgColor = SpotCheckButtonUtils.hexToColor(config.backgroundColor)
        let textColor = SpotCheckButtonUtils.hexToColor(config.textColor)
        let textStyle = SpotCheckButtonUtils.getTextStyle(for: config.buttonSize)
        
        Button(action: config.onPress) {
            HStack(spacing: 6) {
                SpotCheckIcon(icon: config.generatedIcon.isEmpty ? config.icon : config.generatedIcon,
                              buttonSize: config.buttonSize)
                if !config.buttonText.isEmpty {
                    Text(config.buttonText)
                        .font(textStyle)
                        .foregroundColor(textColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(bgColor)
            .cornerRadius(radius)
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .padding(16)
    }
}

struct SideTab: View {
    var config: SpotCheckButtonConfig
    
    @State private var size: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            let bgColor = SpotCheckButtonUtils.hexToColor(config.backgroundColor)
            let textColor = SpotCheckButtonUtils.hexToColor(config.textColor)
            let textStyle = SpotCheckButtonUtils.getTextStyle(for: config.buttonSize)
            let radius = SpotCheckButtonUtils.getBorderRadius(config.cornerRadius, config.buttonSize)
            
            let parts = config.position.split(separator: "_")
            let vertical = parts.first ?? "bottom"
            let horizontal = parts.count > 1 ? parts[1] : "right"
            
            VStack {
                if vertical == "bottom" { Spacer(minLength: 0) }
                
                HStack {
                    if horizontal == "right" { Spacer(minLength: 0) }
                    
                    Button(action: config.onPress) {
                        HStack(spacing: 6) {
                            SpotCheckIcon(
                                icon: config.generatedIcon.isEmpty ? config.icon : config.generatedIcon,
                                buttonSize: config.buttonSize,
                                type: "sideTab"
                            )
                            if !config.buttonText.isEmpty {
                                Text(config.buttonText)
                                    .font(textStyle)
                                    .foregroundColor(textColor)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                        .background(
                            bgColor
                                .clipShape(
                                    RoundedCorner(
                                        radius: radius,
                                        corners: [.topLeft, .topRight]
                                        
                                    )
                                )
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear.onAppear { size = proxy.size }
                            }
                        )
                        
                        
                    }
                    .rotationEffect(rotationAngle(horizontal: String(horizontal)))
                    .offset(x: translationX(horizontal: String(horizontal)),
                            y: translationY(vertical: String(vertical), horizontal: String(horizontal)))
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                    
                    
                    if horizontal == "left" { Spacer(minLength: 0) }
                }
                .padding(.top, vertical == "top" ? 16 : 0)
                .padding(.bottom, vertical == "bottom" ? 16 : 0)
                
                
                if vertical == "top" { Spacer(minLength: 0) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch config.buttonSize {
        case "small": return 8
        case "large": return 16
        default: return 12
        }
    }
    
    private var verticalPadding: CGFloat {
        switch config.buttonSize {
        case "small": return 4
        case "large": return 10
        default: return 6
        }
    }
    
    private func rotationAngle(horizontal: String) -> Angle {
        if horizontal == "left" { return .degrees(90) }
        if horizontal == "right" { return .degrees(-90) }
        return .degrees(0)
    }
    
    private func translationX(horizontal: String) -> CGFloat {
        guard size.width > 0 else { return 0 }
        let width = size.width
        let height = size.height
        if horizontal == "left" {
            return -((width-height) / 2)
        } else if horizontal == "right" {
            return ((width-height) / 2)
        }
        return 0
    }
    
    private func translationY(vertical: String, horizontal: String) -> CGFloat {
        guard horizontal == "left" || horizontal == "right" else { return 0 }
        if vertical == "top" { return size.width / 2 }
        if vertical == "bottom" { return -size.width / 2 }
        return 0
    }
}


struct SpotCheckButton: View {
    var config: SpotCheckButtonConfig

    var body: some View {
        switch config.type {
        case "floatingButton": FloatingButton(config: config)
        case "sideTab": SideTab(config: config)
        case "textButton": TextButton(config: config)
        default: EmptyView()
        }
    }
}
