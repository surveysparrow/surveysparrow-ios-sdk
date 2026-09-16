import SwiftUI

@available(iOS 15.0, *)
struct AnimatedNodeView: View {
    let type: String
    let props: [String: Any]
    let style: [String: Any]
    let children: [[String: Any]]
    let animation: [String: Any]
    let context: BuilderContext
    let key: String
    let hasContent: Bool
    let content: Any?
    let meta: [String: Any]

    @State private var enterProgress: Double = 0
    @State private var exitProgress: Double = 0
    @State private var animatedHeight: CGFloat = 0
    @State private var isFirstRender = true
    @State private var lastLayoutHeight: CGFloat = 0

    private var enterConfig: [String: Any]? { animation["enter"] as? [String: Any] }
    private var exitConfig: [String: Any]? { animation["exit"] as? [String: Any] }
    private var layoutConfig: [String: Any]? { animation["layout"] as? [String: Any] }

    private var enterTriggerActive: Bool {
        guard let enter = enterConfig else { return false }
        guard let trigger = enter["trigger"] else { return true }
        return evaluateCondition(trigger, context: context)
    }

    private var exitTriggerActive: Bool {
        guard let trigger = exitConfig?["trigger"] else { return false }
        return evaluateCondition(trigger, context: context)
    }

    private var shouldAnimateLayout: Bool {
        guard let layout = layoutConfig else { return false }
        guard (layout["type"] as? String) == "height" else { return false }
        if let ifCond = layout["if"] {
            return evaluateCondition(ifCond, context: context)
        }
        return true
    }

    private var currentHeight: CGFloat? {
        toDoubleOpt(style["height"]).flatMap { CGFloat($0) }
    }

    private var styleVisibilityOpacity: Double {
        let resolved = resolveBinding(style["opacity"], context: context)
        return max(0, min(1, toDoubleOpt(resolved) ?? 1.0))
    }

    private var needsAnimated: Bool {
        enterConfig != nil || exitConfig != nil || (layoutConfig?["type"] as? String) == "height"
    }

    private var isSurveyBottomPosition: Bool {
        let details = context.state?["spotCheckDetails"] as? [String: Any] ?? [:]
        let raw = (details["position"] as? String ?? "").lowercased()
        return raw.contains("bottom")
    }

    private var isCardOrMiniCardChromeMode: Bool {
        let details = context.state?["spotCheckDetails"] as? [String: Any] ?? [:]
        let mode = (details["mode"] as? String ?? "").lowercased()
        return mode == "card" || mode == "minicard"
    }

    var body: some View {
        let displayHeight = shouldAnimateLayout && animatedHeight > 0 ? animatedHeight : currentHeight
        let animStyle = computeCombinedStyle()
        let finalOpacity = max(0, min(1, animStyle.opacity * styleVisibilityOpacity))

        buildComponent(
            type: type,
            props: props,
            style: adjustedStyle(height: displayHeight),
            children: children,
            context: context,
            key: key,
            hasContent: hasContent,
            content: content,
            meta: meta
        )
        .id(key)
        .opacity(finalOpacity)
        .allowsHitTesting(styleVisibilityOpacity > 0.01 && finalOpacity > 0.15)
        .scaleEffect(CGFloat(animStyle.scale), anchor: animStyle.scaleAnchor)
        .offset(x: CGFloat(animStyle.translateX), y: CGFloat(animStyle.translateY))
        .onAppear {
            if enterConfig != nil, enterTriggerActive {
                runEnterAnimation()
            } else {
                enterProgress = 1
            }
        }
        .onChange(of: enterTriggerActive) { newVal in
            guard enterConfig != nil else { return }
            if newVal {
                runEnterAnimation()
            } else {
                enterProgress = 0
            }
        }
        .onChange(of: exitTriggerActive) { newVal in
            if newVal {
                runExitAnimation()
            } else {
                exitProgress = 0
            }
        }
        .onChange(of: currentHeight ?? 0) { newHeight in
            runLayoutAnimation(newHeight)
        }
    }

    private func computeCombinedStyle() -> AnimStyle {
        var base = AnimStyle()

        if let enter = enterConfig, enterTriggerActive {
            if let fromRaw = enter["from"] as? [String: Any], let toRaw = enter["to"] as? [String: Any] {
                let from = (resolveBinding(fromRaw, context: context) as? [String: Any]) ?? [:]
                let to = (resolveBinding(toRaw, context: context) as? [String: Any]) ?? [:]
                let p = enterProgress
                
                base.opacity = interpolate(animResolvedDouble(from["opacity"]) ?? 1, animResolvedDouble(to["opacity"]) ?? 1, p)
                base.translateX = interpolate(animResolvedDouble(from["translateX"]) ?? 0, animResolvedDouble(to["translateX"]) ?? 0, p)
                base.translateY = interpolate(animResolvedDouble(from["translateY"]) ?? 0, animResolvedDouble(to["translateY"]) ?? 0, p)
                base.scale = interpolate(animResolvedDouble(from["scale"]) ?? 1, animResolvedDouble(to["scale"]) ?? 1, p)
            }
        }

        if exitTriggerActive, let exit = exitConfig, let toRaw = exit["to"] as? [String: Any] {
            let to = (resolveBinding(toRaw, context: context) as? [String: Any]) ?? [:]
            let p = exitProgress
            let toOpacity = animResolvedDouble(to["opacity"])
            if let t = toOpacity, t < 0.999 {
                base.opacity *= interpolate(1.0, t, p)
            }
            base.translateX += interpolate(0, animResolvedDouble(to["translateX"]) ?? 0, p)
            base.translateY += interpolate(0, animResolvedDouble(to["translateY"]) ?? 0, p)
            base.scale *= interpolate(1.0, animResolvedDouble(to["scale"]) ?? 1, p)
            if let raw = exit["transformOrigin"] {
                base.scaleAnchor = parseTransformOrigin(raw, context: context)
            }
        } else if enterTriggerActive, let enter = enterConfig, let raw = enter["transformOrigin"] {
            base.scaleAnchor = parseTransformOrigin(raw, context: context)
        }

        return base
    }

    private func runEnterAnimation() {
        guard let enter = enterConfig else {
            enterProgress = 1
            return
        }
        guard let durationMs = toDoubleOpt(enter["duration"]) ?? 600 as Double? else {
            enterProgress = 1
            return
        }
        enterProgress = 0
        withAnimation(enterAnimation(durationMs)) {
            enterProgress = 1
        }
    }

    private func runExitAnimation() {
        guard let exit = exitConfig else { return }
        let durationMs = toDoubleOpt(exit["duration"]) ?? 300
        if durationMs <= 0 {
            exitProgress = 1
            if let onComplete = exit["onComplete"] as? String,
               let handler = context.handlers?[onComplete] as? () -> Void {
                handler()
            }
            return
        }
        exitProgress = 0
        withAnimation(exitAnimation()) {
            exitProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + durationMs / 1000.0) {
            if let onComplete = exit["onComplete"] as? String,
               let handler = context.handlers?[onComplete] as? () -> Void {
                handler()
            }
        }
    }

    private func runLayoutAnimation(_ newHeight: CGFloat) {
        guard shouldAnimateLayout, newHeight > 0 else { return }
        if exitTriggerActive {
            animatedHeight = newHeight
            lastLayoutHeight = newHeight
            return
        }
        if isFirstRender {
            animatedHeight = newHeight
            lastLayoutHeight = newHeight
            isFirstRender = false
            return
        }
        let increasing = newHeight > lastLayoutHeight
        let skipSmoothAnimation = isCardOrMiniCardChromeMode && isSurveyBottomPosition && increasing

        let dur = toDoubleOpt(layoutConfig?["duration"]) ?? 300
        let easing = layoutConfig?["easing"] as? String ?? "easeInEaseOut"
        if skipSmoothAnimation {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                animatedHeight = newHeight
            }
        } else {
            withAnimation(mapEasing(easing, duration: dur / 1000.0)) {
                animatedHeight = newHeight
            }
        }
        lastLayoutHeight = newHeight
    }

    private func adjustedStyle(height: CGFloat?) -> [String: Any] {
        var s = style
        if let h = height, h > 0 { s["height"] = h }
        let isAbsolute = styleUsesAbsoluteLayout(s)
        if isAbsolute {
            if toDoubleOpt(s["width"]) == 0 { s.removeValue(forKey: "width") }
            if toDoubleOpt(s["height"]) == 0 { s.removeValue(forKey: "height") }
        }
        s.removeValue(forKey: "opacity")
        s.removeValue(forKey: "transform")
        return s
    }

    private func animResolvedDouble(_ value: Any?) -> Double? {
        toDoubleOpt(resolveBinding(value, context: context))
    }

    private func enterAnimation(_ durationMs: Double) -> Animation {
        return mapEasing(enterConfig?["easing"] as? String ?? "easeOut", duration: durationMs / 1000.0)
    }

    private func exitAnimation() -> Animation {
        let duration = (toDoubleOpt(exitConfig?["duration"]) ?? 300) / 1000.0
        return mapEasing(exitConfig?["easing"] as? String ?? "easeIn", duration: duration)
    }

    private func mapEasing(_ easing: String, duration: Double) -> Animation {
        switch easing {
        case "linear": return .linear(duration: duration)
        case "easeIn": return .easeIn(duration: duration)
        case "easeOut": return .easeOut(duration: duration)
        case "easeInOut", "easeInEaseOut": return .easeInOut(duration: duration)
        default: return .easeOut(duration: duration)
        }
    }

    private func interpolate(_ from: Double, _ to: Double, _ p: Double) -> Double {
        from + (to - from) * p
    }
}

struct AnimStyle {
    var opacity: Double = 1
    var translateX: Double = 0
    var translateY: Double = 0
    var scale: Double = 1
    var scaleAnchor: UnitPoint = .center
}

private func parseTransformOrigin(_ raw: Any?, context: BuilderContext) -> UnitPoint {
    let resolved = resolveBinding(raw, context: context)
    let s = (resolved as? String) ?? ""
    let parts = s.split(separator: " ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard parts.count >= 2 else { return .center }
    func pct(_ p: String) -> CGFloat {
        if p.hasSuffix("%"), let v = Double(p.dropLast()) {
            return CGFloat(v / 100.0)
        }
        return 0.5
    }
    return UnitPoint(x: pct(String(parts[0])), y: pct(String(parts[1])))
}

private func toDoubleOpt(_ val: Any?) -> Double? {
    if let n = val as? Double { return n }
    if let n = val as? Int { return Double(n) }
    if let n = val as? CGFloat { return Double(n) }
    if let n = val as? NSNumber { return n.doubleValue }
    if let s = val as? String { return Double(s) }
    return nil
}
