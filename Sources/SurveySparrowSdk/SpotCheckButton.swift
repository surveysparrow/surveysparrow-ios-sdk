import SwiftUI
import WebKit


fileprivate class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    func get(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

@available(iOS 14.0, *)
@MainActor
fileprivate class ImageLoader: ObservableObject {
    @Published private(set) var state: LoadState = .loading
    
    enum LoadState {
        case loading
        case success(UIImage)
        case failure
    }
    
    private let url: URL
    private var task: URLSessionDataTask?
    
    init(url: URL) {
        self.url = url
    }
    
    func load() {
        let urlString = url.absoluteString
        if let cachedImage = ImageCache.shared.get(forKey: urlString) {
            self.state = .success(cachedImage)
            return
        }
        
        task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let data = data, let loadedImage = UIImage(data: data) {
                    ImageCache.shared.set(loadedImage, forKey: urlString)
                    self.state = .success(loadedImage)
                } else {
                    self.state = .failure
                }
            }
        }
        task?.resume()
    }
    
    func cancel() {
        task?.cancel()
    }
}

@available(iOS 14.0, *)
fileprivate struct CachedAsyncImage<Content: View, Placeholder: View, Failure: View>: View {
    @StateObject private var loader: ImageLoader
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    private let failure: () -> Failure
    
    init(url: URL,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder,
         @ViewBuilder failure: @escaping () -> Failure) {
        _loader = StateObject(wrappedValue: ImageLoader(url: url))
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
    }
    
    var body: some View {
        Group {
            switch loader.state {
            case .loading:
                placeholder()
            case .success(let uiImage):
                content(Image(uiImage: uiImage))
            case .failure:
                failure()
            }
        }
        .onAppear(perform: loader.load)
        .onDisappear(perform: loader.cancel)
    }
}

fileprivate class SVGRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((UIImage?) -> Void)?

    func image(from svgString: String, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        self.completion = completion

        DispatchQueue.main.async {
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
            webView.navigationDelegate = self
            webView.backgroundColor = .clear
            webView.isOpaque = false
            webView.scrollView.isScrollEnabled = false
            self.webView = webView

            let html = """
            <html>
              <head>
                <meta name='viewport' content='width=device-width, initial-scale=1.0, shrink-to-fit=no'>
                <style>
                  body { margin: 0; padding: 0; background: transparent; display: flex; justify-content: center; align-items: center; height: 100vh; }
                  svg { width: 100%; height: 100%; }
                </style>
              </head>
              <body>\(svgString)</body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webView.takeSnapshot(with: nil) { image, error in
                self.completion?(image)
                self.webView = nil
                self.completion = nil
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("SVG rendering failed: \(error)")
        completion?(nil)
        self.webView = nil
        self.completion = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("SVG rendering failed provisionally: \(error)")
        completion?(nil)
        self.webView = nil
        self.completion = nil
    }
}

@available(iOS 14.0, *)
@MainActor
fileprivate class SVGLoader: ObservableObject {
    @Published private(set) var state: ImageLoader.LoadState = .loading

    private let svgString: String
    private var renderer: SVGRenderer?

    init(svgString: String) {
        self.svgString = svgString
    }

    func load(size: CGSize) {
        if let cachedImage = ImageCache.shared.get(forKey: svgString) {
            self.state = .success(cachedImage)
            return
        }

        renderer = SVGRenderer()
        renderer?.image(from: svgString, size: size) { [weak self] image in
            guard let self = self else { return }
            if let image = image {
                ImageCache.shared.set(image, forKey: self.svgString)
                self.state = .success(image)
            } else {
                self.state = .failure
            }
            self.renderer = nil
        }
    }

    func cancel() {
        renderer = nil
    }
}

@available(iOS 14.0, *)
fileprivate struct CachedSVGImageView<Content: View, Placeholder: View, Failure: View>: View {
    @StateObject private var loader: SVGLoader
    private let size: CGSize
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    private let failure: () -> Failure

    init(svgString: String,
         size: CGSize,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder,
         @ViewBuilder failure: @escaping () -> Failure) {
        _loader = StateObject(wrappedValue: SVGLoader(svgString: svgString))
        self.size = size
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            switch loader.state {
            case .loading:
                placeholder()
            case .success(let uiImage):
                content(Image(uiImage: uiImage))
            case .failure:
                failure()
            }
        }
        .onAppear { loader.load(size: size) }
        .onDisappear { loader.cancel() }
    }
}

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

@available(iOS 13.0, *)
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

@available(iOS 13.0, *)
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


@available(iOS 13.0, *)
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
                if #available(iOS 14.0, *) {
                    CachedSVGImageView(svgString: icon, size: CGSize(width: size, height: size)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.clear
                    } failure: {
                        Color.clear
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                } else {
                    InlineSVGView(svgString: icon)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                if #available(iOS 14.0, *) {
                    if let url = URL(string: icon) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color.clear
                        } failure: {
                            Color.clear
                        }
                    } else {
                        Color.clear
                    }
                } else {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
    }
}



@available(iOS 13.0, *)
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


@available(iOS 13.0, *)
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

@available(iOS 13.0, *)
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


@available(iOS 13.0, *)
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
