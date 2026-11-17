import SwiftUI
import WebKit

// MARK: - Builder — Schema JSON → SwiftUI

@available(iOS 15.0, *)
struct BuilderContext {
    var state: [String: Any]?
    var styles: [String: Any]?
    var slots: [String: AnyView]?
    var handlers: [String: Any]?
    // Runs a backend function by name for `$execute` bindings; nil means no-op.
    var execute: ((String, [String: Any]) -> Void)? = nil
}

private struct SpotcheckActionRunnerKey: EnvironmentKey {
    static let defaultValue: ((String, [String: Any]) -> Void)? = nil
}

extension EnvironmentValues {
    var spotcheckActionRunner: ((String, [String: Any]) -> Void)? {
        get { self[SpotcheckActionRunnerKey.self] }
        set { self[SpotcheckActionRunnerKey.self] = newValue }
    }
}

@available(iOS 15.0, *)
struct Builder: View {
    let schema: [String: Any]?
    let context: BuilderContext
    @Environment(\.spotcheckActionRunner) private var actionRunner

    private var effectiveContext: BuilderContext {
        var c = context
        if c.execute == nil { c.execute = actionRunner }
        return c
    }

    var body: some View {
        if let schema = schema {
            renderNode(schema, context: effectiveContext, key: "root")
        }
    }
}

// MARK: - Binding Resolution

@available(iOS 15.0, *)
func resolveBinding(_ value: Any?, context: BuilderContext) -> Any? {
    guard let value = value else { return nil }

    if let dict = value as? [String: Any] {
        // $expr is not supported on native; backend style functions compute values.
        if dict["$expr"] != nil { return nil }

        if let ref = dict["$ref"] as? String {
            let parts = ref.split(separator: ".").map(String.init)
            var result: Any? = ["state": context.state as Any, "styles": context.styles as Any]
            for key in parts {
                if let d = result as? [String: Any] {
                    result = d[key]
                } else {
                    return nil
                }
            }
            return result
        }

        if let path = dict["$path"] as? String {
            let parts = path.split(separator: ".").map(String.init)
            var result: Any? = context.state
            for key in parts {
                if let d = result as? [String: Any] {
                    result = d[key]
                } else {
                    return nil
                }
            }
            return result
        }

        if let handler = dict["$handler"] as? String {
            return context.handlers?[handler]
        }

        // `{"$execute": "group.fn", "args": {...}}`: generic action for taps.
        if let fn = dict["$execute"] as? String {
            let args = dict["args"] as? [String: Any] ?? [:]
            let run = context.execute
            return { () -> Void in run?(fn, args) } as () -> Void
        }

        if let handlerNames = dict["$handlers"] as? [String] {
            let handlers = context.handlers
            return { () -> Void in
                for name in handlerNames {
                    if let h = handlers?[name] as? () -> Void {
                        h()
                    }
                }
            }
        }

        var resolved: [String: Any] = [:]
        for (k, v) in dict {
            if let r = resolveBinding(v, context: context) {
                resolved[k] = r
            }
        }
        return resolved
    }

    if let array = value as? [Any] {
        return array.map { resolveBinding($0, context: context) }
    }

    return value
}

// MARK: - Condition Evaluation

@available(iOS 15.0, *)
func evaluateCondition(_ condition: Any?, context: BuilderContext) -> Bool {
    guard let condition = condition else { return true }

    if let dict = condition as? [String: Any] {
        if let andConds = dict["$and"] as? [Any] {
            return andConds.allSatisfy { evaluateCondition($0, context: context) }
        }
        if let orConds = dict["$or"] as? [Any] {
            return orConds.contains { evaluateCondition($0, context: context) }
        }
        if let notCond = dict["$not"] {
            return !evaluateCondition(notCond, context: context)
        }
        if let eqArr = dict["$eq"] as? [Any], eqArr.count == 2 {
            let left = resolveBinding(eqArr[0], context: context)
            let right = resolveBinding(eqArr[1], context: context)
            return isEqual(left, right)
        }
        if let neArr = dict["$ne"] as? [Any], neArr.count == 2 {
            let left = resolveBinding(neArr[0], context: context)
            let right = resolveBinding(neArr[1], context: context)
            return !isEqual(left, right)
        }
        if let gtArr = dict["$gt"] as? [Any], gtArr.count == 2 {
            let left = toDouble(resolveBinding(gtArr[0], context: context))
            let right = toDouble(resolveBinding(gtArr[1], context: context))
            return left > right
        }
        if let ltArr = dict["$lt"] as? [Any], ltArr.count == 2 {
            let left = toDouble(resolveBinding(ltArr[0], context: context))
            let right = toDouble(resolveBinding(ltArr[1], context: context))
            return left < right
        }
    }

    let resolved = resolveBinding(condition, context: context)
    return isTruthy(resolved)
}

private func isEqual(_ a: Any?, _ b: Any?) -> Bool {
    if a == nil && b == nil { return true }
    if let a = a as? String, let b = b as? String { return a == b }
    if let a = a as? Bool, let b = b as? Bool { return a == b }
    if let a = toDoubleOpt(a), let b = toDoubleOpt(b) { return a == b }
    return false
}

private func isTruthy(_ val: Any?) -> Bool {
    guard let val = val else { return false }
    if let b = val as? Bool { return b }
    if let n = val as? Int { return n != 0 }
    if let n = val as? Double { return n != 0 }
    if let s = val as? String { return !s.isEmpty }
    return true
}

private func toDouble(_ val: Any?) -> Double {
    return toDoubleOpt(val) ?? 0
}

private func toDoubleOpt(_ val: Any?) -> Double? {
    if let n = val as? Double { return n }
    if let n = val as? Int { return Double(n) }
    if let n = val as? CGFloat { return Double(n) }
    if let n = val as? NSNumber { return n.doubleValue }
    if let s = val as? String { return Double(s) }
    return nil
}

/// Style strings from JS (`toObject()` / JSON) may be `String` or `NSString`. Plain `as? String` fails for `NSString`, which forced overlay `alignment` to nil and always centered the survey.
private func styleString(_ style: [String: Any], key: String) -> String? {
    guard let v = style[key] else { return nil }
    if let s = v as? String { return s }
    if let s = v as? NSString { return s as String }
    return nil
}

/// `positioned: true` from JS may bridge as `Bool` or `NSNumber`; `toDoubleOpt` alone misses those cases.
@available(iOS 15.0, *)
func styleUsesAbsoluteLayout(_ style: [String: Any]) -> Bool {
    if (style["position"] as? String) == "absolute" { return true }
    if let b = style["positioned"] as? Bool, b { return true }
    if let n = style["positioned"] as? NSNumber, n.boolValue { return true }
    return toDoubleOpt(style["positioned"]) == 1.0
}

/// Absolute elements should take lower layout priority in a ZStack so the stack sizes to the survey content (RN parity).
/// EXCEPT for the root overlay which must fill the screen to support spacers/alignment.
@available(iOS 15.0, *)
private func isLowPriorityAbsoluteLayout(_ style: [String: Any], role: String? = nil) -> Bool {
    if role == "overlayRoot" { return false }
    return styleUsesAbsoluteLayout(style)
}

// MARK: - Render Node

@available(iOS 15.0, *)
@ViewBuilder
func renderNode(_ node: [String: Any], context: BuilderContext, key: String) -> AnyView {

    if let slot = node["slot"] as? String,
       let slotView = context.slots?[slot] {
        return AnyView(slotView)
    }

    if let ifCond = node["if"],
       !evaluateCondition(ifCond, context: context) {
        return AnyView(EmptyView())
    }

    let type = node["type"] as? String ?? ""
    let props = (node["props"] as? [String: Any])
        .flatMap { resolveBinding($0, context: context) } as? [String: Any] ?? [:]

    let children = node["children"] as? [[String: Any]] ?? []
    let hasContent = node.keys.contains("content")
    let content = hasContent ? resolveBinding(node["content"], context: context) : nil
    let style = props["style"] as? [String: Any] ?? [:]
    let meta = node["meta"] as? [String: Any] ?? [:]

    let viewNode = buildComponent(
        type: type,
        props: props,
        style: style,
        children: children,
        context: context,
        key: key,
        hasContent: hasContent,
        content: content,
        meta: meta
    )

    return AnyView(applyAbsolutePositioning(style: style, content: applyShadow(style, applyScale(style, viewNode)), role: meta["componentRole"] as? String))
}

/// Uniform tap feedback on every platform: dim while pressed.
private struct PressedOpacityButtonStyle: ButtonStyle {
    let pressedOpacity: Double
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? pressedOpacity : 1)
    }
}

/// Optional shadow (shadowRadius, shadowColor, shadowOffsetX/Y); applied outside any clip.
private func applyShadow(_ style: [String: Any], _ view: AnyView) -> AnyView {
    guard let radius = toDoubleOpt(style["shadowRadius"]), radius > 0 else { return view }
    let color = (style["shadowColor"] as? String).map { parseColor($0) } ?? Color.black.opacity(0.33)
    return AnyView(view.shadow(
        color: color,
        radius: CGFloat(radius),
        x: CGFloat(toDoubleOpt(style["shadowOffsetX"]) ?? 0),
        y: CGFloat(toDoubleOpt(style["shadowOffsetY"]) ?? 0)
    ))
}

@available(iOS 15.0, *)
func applyAbsolutePositioning(style: [String: Any], content: AnyView, role: String? = nil) -> AnyView {
    let isAbsolute = styleUsesAbsoluteLayout(style)
    let zIndex = toDoubleOpt(style["zIndex"]) ?? 0

    if isAbsolute {
        let top = toDoubleOpt(style["top"])
        let bottom = toDoubleOpt(style["bottom"])
        let left = toDoubleOpt(style["left"])
        let right = toDoubleOpt(style["right"])

        let alignment: Alignment
        if let alignStr = styleString(style, key: "alignment"), !alignStr.isEmpty {
            alignment = parseAlignment(alignStr)
        } else {
            var vAlignment: VerticalAlignment = .center
            if top != nil { vAlignment = .top }
            else if bottom != nil { vAlignment = .bottom }

            var hAlignment: HorizontalAlignment = .center
            if left != nil { hAlignment = .leading }
            else if right != nil { hAlignment = .trailing }

            alignment = Alignment(horizontal: hAlignment, vertical: vAlignment)
        }

        let positioned = content
            .padding(.top, CGFloat(top ?? 0))
            .padding(.bottom, CGFloat(bottom ?? 0))
            .padding(.leading, CGFloat(left ?? 0))
            .padding(.trailing, CGFloat(right ?? 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .zIndex(zIndex)

        if isLowPriorityAbsoluteLayout(style, role: role) {
            return AnyView(positioned.layoutPriority(-1))
        }
        return AnyView(positioned)
    } else {
        return AnyView(content.zIndex(zIndex))
    }
}




// MARK: - Stable ForEach identity (miniCard: do NOT use array index alone — conditional rows shift indices and recreate WKWebView).

@available(iOS 15.0, *)
private func stableSchemaChildId(child: [String: Any], index: Int) -> String {
    let type = child["type"] as? String ?? "node"
    let meta = child["meta"] as? [String: Any] ?? [:]
    if let wv = meta["webViewType"] as? String, !wv.isEmpty {
        return "wv-\(wv)"
    }
    if let role = meta["componentRole"] as? String, !role.isEmpty {
        return "role-\(role)"
    }
    if let slot = child["slot"] as? String, !slot.isEmpty {
        return "slot-\(slot)"
    }
    return "\(type)-\(index)"
}

@available(iOS 15.0, *)
private struct SchemaChildItem: Identifiable {
    let id: String
    let node: [String: Any]
}

/// Builds one stable `id` per child for `ForEach`. Prefer semantic ids (role / webViewType) so inserting
/// conditional rows (miniCard) does not shift identity of unrelated siblings (e.g. WebView).
@available(iOS 15.0, *)
private func makeSchemaChildItems(_ children: [[String: Any]]) -> [SchemaChildItem] {
    var seen = Set<String>()
    var out: [SchemaChildItem] = []
    out.reserveCapacity(children.count)
    for (idx, child) in children.enumerated() {
        var sid = stableSchemaChildId(child: child, index: idx)
        if seen.contains(sid) {
            sid = "\(sid)-\(idx)"
        }
        seen.insert(sid)
        out.append(SchemaChildItem(id: sid, node: child))
    }
    return out
}

/// Minimum tap target from backend `getCloseButtonStyles` → `closeButtonMinimumTapTarget` (`context.styles`).
@available(iOS 15.0, *)
@ViewBuilder
fileprivate func applyCloseButtonMinimumHitTarget<Content: View>(
    isCloseButton: Bool,
    context: BuilderContext,
    @ViewBuilder content: () -> Content
) -> some View {
    if isCloseButton {
        let tap = context.styles?["closeButtonMinimumTapTarget"] as? [String: Any]
        let defaultMin: CGFloat = 44
        let minW: CGFloat = {
            guard let v = toDoubleOpt(tap?["minWidth"]), v > 0 else { return defaultMin }
            return CGFloat(v)
        }()
        let minH: CGFloat = {
            guard let v = toDoubleOpt(tap?["minHeight"]), v > 0 else { return defaultMin }
            return CGFloat(v)
        }()
        content()
            .frame(minWidth: minW, minHeight: minH, alignment: .center)
            .contentShape(Rectangle())
    } else {
        content()
    }
}

// MARK: - Component Factory

@available(iOS 15.0, *)
func buildComponent(
    type: String,
    props: [String: Any],
    style: [String: Any],
    children: [[String: Any]],
    context: BuilderContext,
    key: String,
    hasContent: Bool,
    content: Any?,
    meta: [String: Any] = [:]
) -> AnyView {

    let childItems = makeSchemaChildItems(children)

    // ✅ Reusable children renderer — `id` is semantic (role / webViewType), not raw array offset.
    let renderedChildren = AnyView(
        ForEach(childItems) { item in
            renderNode(item.node, context: context, key: "\(key)-\(item.id)")
        }
    )

    switch type {

    case "SafeArea":
        // Schema-driven: only `wrapper` uses `meta.componentRole === "overlayRoot"` (survey overlay + flex Spacers).
        // SpotCheck button is also `SafeArea` (`entryPointButton`) — must use `applyContainerStyle` or layout/injection break.
        // Do not gate on `style.alignment`: `wrapperStyles` can be briefly empty or non-String during init, which skipped
        // overlay layout and collapsed the WebView subtree (injection pipeline / WKWebView registration failed).
        if (meta["componentRole"] as? String) == "overlayRoot" {
            return AnyView(
                applyOverlayContainerStyle(style, state: context.state) {
                    renderedChildren
                }
            )
        }
        return AnyView(
            applyContainerStyle(style) {
                renderedChildren
            }
        )

    case "ZStack":
        let zAlign = flexZAlignment(style, base: parseAlignment(styleString(style, key: "alignment")))
        let w = toDoubleOpt(style["width"])
        let h = toDoubleOpt(style["height"])
        // New keys only; zero insets when absent.
        let zPad = EdgeInsets(
            top: CGFloat(styleNum(style, "paddingTop") ?? styleNum(style, "paddingVertical") ?? 0),
            leading: CGFloat(styleNum(style, "paddingLeft") ?? styleNum(style, "paddingHorizontal") ?? 0),
            bottom: CGFloat(styleNum(style, "paddingBottom") ?? styleNum(style, "paddingVertical") ?? 0),
            trailing: CGFloat(styleNum(style, "paddingRight") ?? styleNum(style, "paddingHorizontal") ?? 0)
        )
        return AnyView(
            ZStack(alignment: zAlign) {
                renderedChildren
            }
            .padding(zPad)
            .frame(
                width: w.flatMap { $0 < 0 ? nil : CGFloat($0) },
                height: h.flatMap { $0 < 0 ? nil : CGFloat($0) }
            )
            .frame(
                maxWidth: (w ?? 0) < 0 ? .infinity : nil,
                maxHeight: (h ?? 0) < 0 ? .infinity : nil
            )
            .padding(marginInsets(style))
        )

    case "VStack":
        return AnyView(
            applyContainerStyle(style) {
                renderedChildren
            }
        )

    case "HStack":
        // justifyContent (when present) overrides horizontalArrangement.
        let justify = styleString(style, key: "justifyContent")?.lowercased()
        let justifyArrangement: String? = {
            switch justify {
            case "flex-start", "start": return "start"
            case "flex-end", "end": return "end"
            case "center": return "center"
            default: return nil
            }
        }()
        let arrangement = justifyArrangement ?? (style["horizontalArrangement"] as? String)?.lowercased() ?? ""
        let rowAlign = flexVAlign(styleString(style, key: "alignItems")) ?? .center
        let pv = toDoubleOpt(style["paddingVertical"]) ?? 0
        let pb = toDoubleOpt(style["paddingBottom"]) ?? 0
        // New keys only; zero when absent.
        let pt = styleNum(style, "paddingTop")
        let pl = styleNum(style, "paddingLeft") ?? styleNum(style, "paddingHorizontal") ?? 0
        let pr = styleNum(style, "paddingRight") ?? styleNum(style, "paddingHorizontal") ?? 0
        let gap = CGFloat(toDouble(style["gap"]))
        let stack: AnyView
        if arrangement == "end" || arrangement == "trailing" {
            stack = AnyView(
                HStack(alignment: rowAlign, spacing: gap) {
                    Spacer(minLength: 0)
                    renderedChildren
                }
            )
        } else if arrangement == "start" || arrangement == "leading" {
            stack = AnyView(
                HStack(alignment: rowAlign, spacing: gap) {
                    renderedChildren
                    Spacer(minLength: 0)
                }
            )
        } else if justifyArrangement == "center" {
            stack = AnyView(
                HStack(alignment: rowAlign, spacing: gap) {
                    Spacer(minLength: 0)
                    renderedChildren
                    Spacer(minLength: 0)
                }
            )
        } else {
            stack = AnyView(
                HStack(alignment: rowAlign, spacing: gap) {
                    renderedChildren
                }
            )
        }
        return AnyView(
            stack
                // paddingTop replaces the vertical top inset when present.
                .padding(.top, CGFloat(pt ?? pv))
                .padding(.bottom, CGFloat(pv))
                .padding(.bottom, CGFloat(pb))
                .padding(.leading, CGFloat(pl))
                .padding(.trailing, CGFloat(pr))
                .frame(maxWidth: (toDoubleOpt(style["width"]) ?? 0) < 0 ? .infinity : nil)
                .padding(marginInsets(style))
        )

    case "Frame":
        return AnyView(
            applyFrameStyle(style) {
                renderedChildren
            }
        )

    case "Button":
        let onTap = props["onTap"]
        // Schema may set `onLayout: { "$handler": "handleSideTabLayout" }`. Handlers live in `[String: Any]`;
        // casting `Any` → `([String: Any]) -> Void` often fails. Detect presence by key and call
        // `execute("spotCheckButton.handleSideTabLayout")` from `SideTabLayoutReporter` (Expo parity).
        let reportSideTabLayout = props["onLayout"] != nil
        let isCloseButton = (meta["componentRole"] as? String) == "closeButton"
        return AnyView(
            applyCloseButtonMinimumHitTarget(isCloseButton: isCloseButton, context: context) {
                Button(action: {
                    if let handler = onTap as? () -> Void {
                        handler()
                    } else if let asyncHandler = onTap as? () async -> Void {
                        Task { await asyncHandler() }
                    }
                }) {
                    Group {
                        if reportSideTabLayout {
                            SideTabLayoutReporter {
                                applyContainerStyle(style) {
                                    renderedChildren
                                }
                            }
                        } else {
                            applyContainerStyle(style) {
                                renderedChildren
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressedOpacityButtonStyle(
                    pressedOpacity: toDoubleOpt(props["pressedOpacity"]) ?? 0.6
                ))
            }
        )

    case "Image":
        return AnyView(
            buildImageView(props: props, style: style)
        )

    case "SvgXml":
        return AnyView(
            buildSvgXmlView(props: props, style: style)
        )

    case "Text":
        if hasContent, let text = content as? String {
            return AnyView(
                buildTextView(text: text, style: style)
            )
        } else {
            return AnyView(EmptyView())
        }

    case "CloseButton":
        return AnyView(
            CloseButtonComponent(context: context)
        )

    case "WebViewRenderer":
        return AnyView(
            WebViewRendererComponent(props: props, meta: meta, context: context, builderKey: key)
        )

    default:
        return AnyView(EmptyView())
    }
}

// MARK: - Side tab layout (RN `onLayout` parity for handleSideTabLayout.js)

@available(iOS 15.0, *)
private struct SpotCheckButtonLayoutKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Measures the button label and calls `handleSideTabLayout` with RN-shaped `event` (see Expo `Pressable` `onLayout`).
/// Uses `EnvironmentObject` so we never rely on casting handlers out of `[String: Any]`.
@available(iOS 15.0, *)
private struct SideTabLayoutReporter<Content: View>: View {
    @EnvironmentObject private var sdk: SpotCheckSDK
    @ViewBuilder let content: () -> Content

    @State private var lastWidth: CGFloat = -1

    var body: some View {
        content()
            .overlay(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: SpotCheckButtonLayoutKey.self,
                            value: geo.size
                        )
                        .allowsHitTesting(false)
                }
            )
            .onPreferenceChange(SpotCheckButtonLayoutKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }

                let diff = abs(size.width - lastWidth)
                if diff < 0.5 { return }

                lastWidth = size.width

                let event: [String: Any] = [
                    "nativeEvent": [
                        "layout": [
                            "width": Double(size.width),
                            "height": Double(size.height),
                        ],
                    ],
                ]

                Task {
                    await sdk.executeBridge.execute(
                        "spotCheckButton.handleSideTabLayout",
                        params: [
                            "event": event,
                        ]
                    )
                }
            }
    }
}

// MARK: - Style Helpers

// Finite number for a style key; nil when absent or NaN/inf.
private func styleNum(_ style: [String: Any], _ key: String) -> Double? {
    guard let v = toDoubleOpt(style[key]), v.isFinite else { return nil }
    return v
}

// True when any of the keys holds a number.
private func styleHasAny(_ style: [String: Any], _ keys: [String]) -> Bool {
    keys.contains { styleNum(style, $0) != nil }
}

private let sidePaddingKeys = ["paddingTop", "paddingBottom", "paddingLeft", "paddingRight"]
private let newMarginKeys = ["margin", "marginTop", "marginBottom", "marginLeft", "marginRight"]

// Container padding: per-side wins, else today's additive padding + axis value.
private func containerPaddingInsets(_ style: [String: Any]) -> EdgeInsets {
    let p = styleNum(style, "padding") ?? 0
    let ph = styleNum(style, "paddingHorizontal") ?? 0
    let pv = styleNum(style, "paddingVertical") ?? 0
    return EdgeInsets(
        top: CGFloat(styleNum(style, "paddingTop") ?? p + pv),
        leading: CGFloat(styleNum(style, "paddingLeft") ?? p + ph),
        bottom: CGFloat(styleNum(style, "paddingBottom") ?? p + pv),
        trailing: CGFloat(styleNum(style, "paddingRight") ?? p + ph)
    )
}

// RN margin: per-side, then axis, then margin; zero when absent.
private func marginInsets(_ style: [String: Any]) -> EdgeInsets {
    let m = styleNum(style, "margin")
    let mh = styleNum(style, "marginHorizontal") ?? m ?? 0
    let mv = styleNum(style, "marginVertical") ?? m ?? 0
    return EdgeInsets(
        top: CGFloat(styleNum(style, "marginTop") ?? mv),
        leading: CGFloat(styleNum(style, "marginLeft") ?? mh),
        bottom: CGFloat(styleNum(style, "marginBottom") ?? mv),
        trailing: CGFloat(styleNum(style, "marginRight") ?? mh)
    )
}

// RN alignItems/justifyContent token → horizontal alignment.
private func flexHAlign(_ token: String?) -> HorizontalAlignment? {
    switch token?.lowercased() {
    case "flex-start", "start": return .leading
    case "center": return .center
    case "flex-end", "end": return .trailing
    default: return nil
    }
}

// RN alignItems/justifyContent token → vertical alignment.
private func flexVAlign(_ token: String?) -> VerticalAlignment? {
    switch token?.lowercased() {
    case "flex-start", "start": return .top
    case "center": return .center
    case "flex-end", "end": return .bottom
    default: return nil
    }
}

// ZStack/Frame alignment: column justifyContent → vertical, alignItems → horizontal; base when absent.
private func flexZAlignment(_ style: [String: Any], base: Alignment) -> Alignment {
    let h = flexHAlign(styleString(style, key: "alignItems"))
    let v = flexVAlign(styleString(style, key: "justifyContent"))
    if h == nil && v == nil { return base }
    return Alignment(horizontal: h ?? base.horizontal, vertical: v ?? base.vertical)
}

// RN flex stack used only when justifyContent/alignItems is present.
@available(iOS 15.0, *)
@ViewBuilder
private func flexStack<C: View>(
    row: Bool,
    gap: CGFloat,
    justify: String?,
    alignItems: String?,
    defaultH: HorizontalAlignment,
    @ViewBuilder content: () -> C
) -> some View {
    let j = justify?.lowercased()
    let lead = j == "flex-end" || j == "end" || j == "center"
    let trail = j == "flex-start" || j == "start" || j == "center"
    if row {
        HStack(spacing: 0) {
            if lead { Spacer(minLength: 0) }
            HStack(alignment: flexVAlign(alignItems) ?? .center, spacing: gap) { content() }
            if trail { Spacer(minLength: 0) }
        }
    } else {
        VStack(alignment: flexHAlign(alignItems) ?? defaultH, spacing: 0) {
            if lead { Spacer(minLength: 0) }
            VStack(alignment: flexHAlign(alignItems) ?? defaultH, spacing: gap) { content() }
            if trail { Spacer(minLength: 0) }
        }
    }
}

// Border shape choices (AnyShape needs iOS 16).
@available(iOS 15.0, *)
private enum ErasedShape: Shape {
    case rect
    case circle
    case rounded(CGFloat)
    case roundedCircular(CGFloat)
    case selective(CGFloat, ContainerCornerMask)

    func path(in rect: CGRect) -> Path {
        switch self {
        case .rect: return Rectangle().path(in: rect)
        case .circle: return Circle().path(in: rect)
        case .rounded(let r): return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect)
        case .roundedCircular(let r): return RoundedRectangle(cornerRadius: r).path(in: rect)
        case .selective(let r, let c): return SelectiveRoundedRectangle(radius: r, corners: c).path(in: rect)
        }
    }
}

// Stroke drawn inside the shape when borderWidth > 0; nothing otherwise.
@available(iOS 15.0, *)
@ViewBuilder
private func borderOverlay(_ style: [String: Any], shape: ErasedShape) -> some View {
    if let w = styleNum(style, "borderWidth"), w > 0 {
        shape
            .stroke(parseColor(styleString(style, key: "borderColor") ?? "#000000"), lineWidth: CGFloat(w))
            .padding(CGFloat(w / 2))
            .allowsHitTesting(false)
    }
}

// Scale only when the key is present.
@available(iOS 15.0, *)
private func applyScale(_ style: [String: Any], _ view: AnyView) -> AnyView {
    guard let s = styleNum(style, "scale") else { return view }
    return AnyView(view.scaleEffect(CGFloat(s)))
}

/// Which corners use `radius` (matches RN-style per-corner radii from `getSpotCheckButtonStyles.js` side tab).
@available(iOS 15.0, *)
private struct ContainerCornerMask: OptionSet {
    let rawValue: UInt8
    static let topLeft = ContainerCornerMask(rawValue: 1 << 0)
    static let topRight = ContainerCornerMask(rawValue: 1 << 1)
    static let bottomLeft = ContainerCornerMask(rawValue: 1 << 2)
    static let bottomRight = ContainerCornerMask(rawValue: 1 << 3)
}

@available(iOS 15.0, *)
private func containerCornerMaskFromStyle(
    borderRadiusTopLeft: Double,
    borderRadiusTopRight: Double,
    borderRadiusBottomLeft: Double,
    borderRadiusBottomRight: Double
) -> ContainerCornerMask {
    var corners = ContainerCornerMask()
    if borderRadiusTopLeft > 0 { corners.insert(.topLeft) }
    if borderRadiusTopRight > 0 { corners.insert(.topRight) }
    if borderRadiusBottomLeft > 0 { corners.insert(.bottomLeft) }
    if borderRadiusBottomRight > 0 { corners.insert(.bottomRight) }
    return corners
}

/// Selective corner rounding without UIKit (SPM / `swift build` friendly).
@available(iOS 15.0, *)
private struct SelectiveRoundedRectangle: Shape {
    var radius: CGFloat
    var corners: ContainerCornerMask

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        let tl = corners.contains(.topLeft)
        let tr = corners.contains(.topRight)
        let bl = corners.contains(.bottomLeft)
        let br = corners.contains(.bottomRight)

        var p = Path()
        p.move(to: CGPoint(x: minX + (tl ? r : 0), y: minY))

        p.addLine(to: CGPoint(x: maxX - (tr ? r : 0), y: minY))
        if tr {
            p.addArc(
                center: CGPoint(x: maxX - r, y: minY + r),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: maxX, y: minY))
        }

        p.addLine(to: CGPoint(x: maxX, y: maxY - (br ? r : 0)))
        if br {
            p.addArc(
                center: CGPoint(x: maxX - r, y: maxY - r),
                radius: r,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: maxX, y: maxY))
        }

        p.addLine(to: CGPoint(x: minX + (bl ? r : 0), y: maxY))
        if bl {
            p.addArc(
                center: CGPoint(x: minX + r, y: maxY - r),
                radius: r,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: minX, y: maxY))
        }

        p.addLine(to: CGPoint(x: minX, y: minY + (tl ? r : 0)))
        if tl {
            p.addArc(
                center: CGPoint(x: minX + r, y: minY + r),
                radius: r,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: minX, y: minY))
        }

        p.closeSubpath()
        return p
    }
}

/// `GeometryReader.safeAreaInsets` is often **zero** for full-screen overlays (inset already “consumed” by the
/// layout engine). UIKit `UIView.safeAreaInsets` on a full-screen subview still reports notch / home-indicator
/// insets — merge both with per-edge max (see `OverlaySafeAreaPaddedContent`).
@available(iOS 15.0, *)
private func mergeEdgeInsets(_ a: EdgeInsets, _ b: EdgeInsets) -> EdgeInsets {
    EdgeInsets(
        top: max(a.top, b.top),
        leading: max(a.leading, b.leading),
        bottom: max(a.bottom, b.bottom),
        trailing: max(a.trailing, b.trailing)
    )
}

/// Full-screen probe so `safeAreaInsets` match the window (Dynamic Island, home indicator) when SwiftUI geometry
/// reports zeros.
@available(iOS 15.0, *)
private final class SafeAreaInsetProbeView: UIView {
    var onInsetsChanged: ((UIEdgeInsets) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onInsetsChanged?(safeAreaInsets)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onInsetsChanged?(safeAreaInsets)
    }
}

@available(iOS 15.0, *)
private struct SafeAreaInsetsReporter: UIViewRepresentable {
    @Binding var insets: EdgeInsets

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $insets)
    }

    func makeUIView(context: Context) -> SafeAreaInsetProbeView {
        let v = SafeAreaInsetProbeView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        wire(v, coordinator: context.coordinator)
        return v
    }

    func updateUIView(_ uiView: SafeAreaInsetProbeView, context: Context) {
        context.coordinator.binding = $insets
        wire(uiView, coordinator: context.coordinator)
    }

    private func wire(_ view: SafeAreaInsetProbeView, coordinator: Coordinator) {
        view.onInsetsChanged = { ui in
            coordinator.apply(ui)
        }
    }

    final class Coordinator {
        var binding: Binding<EdgeInsets>

        init(binding: Binding<EdgeInsets>) {
            self.binding = binding
        }

        func apply(_ ui: UIEdgeInsets) {
            let next = EdgeInsets(
                top: ui.top,
                leading: ui.left,
                bottom: ui.bottom,
                trailing: ui.right
            )
            DispatchQueue.main.async {
                self.binding.wrappedValue = next
            }
        }
    }
}

/// Holds `@State` for UIKit-measured insets (cannot live inside `applyOverlayContainerStyle` function).
@available(iOS 15.0, *)
private struct OverlaySafeAreaPaddedContent<Content: View>: View {
    let alignmentToken: String?
    let state: [String: Any]?
    let rotation: Double
    let flexDirection: String
    let gap: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var uiKitInsets = EdgeInsets()

    var body: some View {
        GeometryReader { geo in
            let merged = mergeEdgeInsets(geo.safeAreaInsets, uiKitInsets)
            overlayFlexColumn(alignmentToken: alignmentToken) {
                Group {
                    if flexDirection == "row" {
                        HStack(spacing: gap) {
                            content()
                        }
                    } else {
                        VStack(spacing: 0) {
                            content()
                        }
                    }
                }
                .rotationEffect(.radians(rotation))
            }
            .padding(overlaySafeAreaInsets(merged, state: state))
        }
        .background(
            SafeAreaInsetsReporter(insets: $uiKitInsets)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}

/// Pads the survey column (VStack + ZStack with WebView + close) with device safe-area insets so native UI and
/// WKWebView share the same layout region. Matches Expo `SafeAreaView` on the wrapper. Position-aware: top / center /
/// bottom / fullScreen (see `overlaySafeAreaInsets`). Does not change close-button styles.
@available(iOS 15.0, *)
private func overlaySafeAreaInsets(_ device: EdgeInsets, state: [String: Any]?) -> EdgeInsets {
    guard let details = state?["spotCheckDetails"] as? [String: Any] else {
        return EdgeInsets(top: device.top, leading: device.leading, bottom: device.bottom, trailing: device.trailing)
    }
    if details["isFullScreenMode"] as? Bool == true {
        return EdgeInsets(top: device.top, leading: device.leading, bottom: device.bottom, trailing: device.trailing)
    }
    let raw = (details["position"] as? String ?? "").lowercased()
    // Check "bottom" before "top" — e.g. "bottomCenter" contains substring "top" inside "bottom".
    let isBottom = raw.contains("bottom")
    let isTop = !isBottom && raw.contains("top")

    if isBottom {
        return EdgeInsets(top: 0, leading: device.leading, bottom: device.bottom, trailing: device.trailing)
    }
    if isTop {
        return EdgeInsets(top: device.top, leading: device.leading, bottom: 0, trailing: device.trailing)
    }
    return EdgeInsets(top: device.top, leading: device.leading, bottom: device.bottom, trailing: device.trailing)
}

/// Expo overlay uses column flex + `justifyContent` (`getWrapperStyles.js`). A plain `ZStack(alignment:)`
/// often lays out the inner `VStack` at full offered height, so the card **looks** centered — use `Spacer`s
/// like RN column + justifyContent (see `overlayFlexColumn`).
@available(iOS 15.0, *)
func applyOverlayContainerStyle<Content: View>(
    _ style: [String: Any],
    state: [String: Any]?,
    @ViewBuilder content: @escaping () -> Content
) -> some View {
    let width = toDoubleOpt(style["width"])
    let height = toDoubleOpt(style["height"])
    let opacity = toDoubleOpt(style["opacity"]) ?? 1.0
    let bgColor = parseColor(style["color"] as? String ?? style["backgroundColor"] as? String)
    let borderRadius = toDoubleOpt(style["borderRadius"]) ?? 0
    let borderRadiusTopLeft = toDoubleOpt(style["borderRadiusTopLeft"]) ?? 0
    let borderRadiusTopRight = toDoubleOpt(style["borderRadiusTopRight"]) ?? 0
    let borderRadiusBottomLeft = toDoubleOpt(style["borderRadiusBottomLeft"]) ?? 0
    let borderRadiusBottomRight = toDoubleOpt(style["borderRadiusBottomRight"]) ?? 0
    let gap = toDoubleOpt(style["gap"]) ?? 0
    let flexDirection = style["flexDirection"] as? String ?? "column"
    let rotation = toDoubleOpt(style["rotation"]) ?? 0
    let translateX = toDoubleOpt(style["translateX"]) ?? 0
    let translateY = toDoubleOpt(style["translateY"]) ?? 0
    let isAbsolute = styleUsesAbsoluteLayout(style)
    var adjustedWidth = width
    var adjustedHeight = height
    if isAbsolute {
        if adjustedWidth == 0 { adjustedWidth = nil }
        if adjustedHeight == 0 { adjustedHeight = nil }
    }

    let perCornerRadii = (
        borderRadiusTopLeft + borderRadiusTopRight + borderRadiusBottomLeft + borderRadiusBottomRight
    )
    let cornerMask = containerCornerMaskFromStyle(
        borderRadiusTopLeft: borderRadiusTopLeft,
        borderRadiusTopRight: borderRadiusTopRight,
        borderRadiusBottomLeft: borderRadiusBottomLeft,
        borderRadiusBottomRight: borderRadiusBottomRight
    )
    let perCornerMax = max(borderRadiusTopLeft, borderRadiusTopRight, borderRadiusBottomLeft, borderRadiusBottomRight)

    return OverlaySafeAreaPaddedContent(
        alignmentToken: styleString(style, key: "alignment"),
        state: state,
        rotation: rotation,
        flexDirection: flexDirection,
        gap: CGFloat(gap),
        content: content
    )
    .frame(width: adjustedWidth.flatMap { CGFloat($0) }, height: adjustedHeight.flatMap { CGFloat($0) })
     .offset(x: CGFloat(translateX), y: CGFloat(translateY))
    // Same sum as padding + paddingHorizontal + paddingVertical; per-side keys win.
    .padding(containerPaddingInsets(style))
    .background(containerBackground(
        bgColor: bgColor,
        borderRadius: borderRadius,
        perCornerRadiiSum: perCornerRadii,
        perCornerMax: perCornerMax,
        cornerMask: cornerMask,
        layoutWidth: adjustedWidth.map { CGFloat($0) },
        layoutHeight: adjustedHeight.map { CGFloat($0) }
    ))
    .overlay(borderOverlay(style, shape: containerShape(
        borderRadius: borderRadius,
        perCornerRadiiSum: perCornerRadii,
        perCornerMax: perCornerMax,
        cornerMask: cornerMask,
        layoutWidth: adjustedWidth.map { CGFloat($0) },
        layoutHeight: adjustedHeight.map { CGFloat($0) }
    )))
    .background(backdropMaterial(blur: toDoubleOpt(style["backdropBlur"]) ?? 0))
    // Zero when no margin keys are sent.
    .padding(marginInsets(style))
    .opacity(opacity)
    .allowsHitTesting(opacity > 0.01)
}

// Backdrop blur behind the overlay (SwiftUI material approximates the blur radius).
@available(iOS 15.0, *)
@ViewBuilder
private func backdropMaterial(blur: Double) -> some View {
    if blur > 0 {
        Rectangle().fill(blur >= 10 ? .regularMaterial : .ultraThinMaterial)
    }
}

/// Mirrors Expo `justifyContent`: top → content then Spacer; bottom → Spacer then content; center → both Spacers.
@available(iOS 15.0, *)
@ViewBuilder
private func overlayFlexColumn<Content: View>(
    alignmentToken: String?,
    @ViewBuilder content: () -> Content
) -> some View {
    let s = (alignmentToken ?? "center").lowercased()
    let isBottom = s.contains("bottom")
    let isTop = s.contains("top")
    let isCenter = !isBottom && !isTop

    VStack(spacing: 0) {
        if isBottom || isCenter {
            Spacer(minLength: 0)
        }
        content()
        if isTop || isCenter {
            Spacer(minLength: 0)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@available(iOS 15.0, *)
func applyContainerStyle<Content: View>(_ style: [String: Any], @ViewBuilder content: @escaping () -> Content) -> some View {
    let width = toDoubleOpt(style["width"])
    let height = toDoubleOpt(style["height"])
    let opacity = toDoubleOpt(style["opacity"]) ?? 1.0
    let bgColor = parseColor(style["color"] as? String ?? style["backgroundColor"] as? String)
    let alignment = parseAlignment(styleString(style, key: "alignment"))
    let borderRadius = toDoubleOpt(style["borderRadius"]) ?? 0
    let borderRadiusTopLeft = toDoubleOpt(style["borderRadiusTopLeft"]) ?? 0
    let borderRadiusTopRight = toDoubleOpt(style["borderRadiusTopRight"]) ?? 0
    let borderRadiusBottomLeft = toDoubleOpt(style["borderRadiusBottomLeft"]) ?? 0
    let borderRadiusBottomRight = toDoubleOpt(style["borderRadiusBottomRight"]) ?? 0
    let padding = toDoubleOpt(style["padding"]) ?? 0
    let gap = toDoubleOpt(style["gap"]) ?? 0
    let flexDirection = style["flexDirection"] as? String ?? "column"
    let rotation = toDoubleOpt(style["rotation"]) ?? 0
    let translateX = toDoubleOpt(style["translateX"]) ?? 0
    let translateY = toDoubleOpt(style["translateY"]) ?? 0
    let isAbsolute = styleUsesAbsoluteLayout(style)

    var adjustedWidth = width
    var adjustedHeight = height
    if isAbsolute {
        if adjustedWidth == 0 { adjustedWidth = nil }
        if adjustedHeight == 0 { adjustedHeight = nil }
    }
    // RN: width/height -1 means fill — pass nil into RotatedLayout and expand with frame(maxWidth:).
    if let w = adjustedWidth, w < 0 { adjustedWidth = nil }
    if let h = adjustedHeight, h < 0 { adjustedHeight = nil }
    let expandLayoutWidth = (width ?? 0) < 0
    let expandLayoutHeight = (height ?? 0) < 0
    let padInsets = containerPaddingInsets(style)
    let hasSidePadding = styleHasAny(style, sidePaddingKeys)
    // RN padding sits inside a fixed box (floating button rings); SwiftUI pads outside, so shrink the inner box.
    if rotation == 0, padding > 0 || hasSidePadding, let w = adjustedWidth, let h = adjustedHeight, w > 0, h > 0 {
        // Per-side keys shrink by the real insets; otherwise today's 2 × padding.
        let shrinkW = hasSidePadding ? Double(padInsets.leading + padInsets.trailing) : 2 * padding
        let shrinkH = hasSidePadding ? Double(padInsets.top + padInsets.bottom) : 2 * padding
        adjustedWidth = max(0, w - shrinkW)
        adjustedHeight = max(0, h - shrinkH)
    }
    let hasFlexKeys = styleString(style, key: "justifyContent") != nil || styleString(style, key: "alignItems") != nil

    let perCornerRadii = (
        borderRadiusTopLeft + borderRadiusTopRight + borderRadiusBottomLeft + borderRadiusBottomRight
    )
    let cornerMask = containerCornerMaskFromStyle(
        borderRadiusTopLeft: borderRadiusTopLeft,
        borderRadiusTopRight: borderRadiusTopRight,
        borderRadiusBottomLeft: borderRadiusBottomLeft,
        borderRadiusBottomRight: borderRadiusBottomRight
    )
    let perCornerMax = max(borderRadiusTopLeft, borderRadiusTopRight, borderRadiusBottomLeft, borderRadiusBottomRight)
    let borderShape = containerShape(
        borderRadius: borderRadius,
        perCornerRadiiSum: perCornerRadii,
        perCornerMax: perCornerMax,
        cornerMask: cornerMask,
        layoutWidth: adjustedWidth.map { CGFloat($0) },
        layoutHeight: adjustedHeight.map { CGFloat($0) }
    )

    // Full-width survey column (wrapper, rows) needs leading alignment + maxWidth so HStacks match padded width.
    // Fixed small frames (e.g. miniCard close 32×32) must stay column-centered or the icon sits on the leading edge of the circle.
    let isFullWidthColumn =
        flexDirection != "row"
        && (expandLayoutWidth || (width.map { $0 > 80 } ?? false))

    return RotatedLayout(rotation: rotation, width: adjustedWidth, height: adjustedHeight, alignment: alignment) {
        Group {
            if hasFlexKeys {
                // Only when justifyContent/alignItems is sent.
                flexStack(
                    row: flexDirection == "row",
                    gap: CGFloat(gap),
                    justify: styleString(style, key: "justifyContent"),
                    alignItems: styleString(style, key: "alignItems"),
                    defaultH: isFullWidthColumn ? .leading : .center
                ) {
                    content()
                }
                .frame(maxWidth: isFullWidthColumn ? .infinity : nil)
            } else if flexDirection == "row" {
                HStack(spacing: CGFloat(gap)) {
                    content()
                }
            } else if isFullWidthColumn {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // ZStack keeps circular spot-check layers centered on both axes (VStack top-aligns a single child).
                ZStack(alignment: .center) {
                    content()
                }
            }
        }
    }
    .offset(x: CGFloat(translateX), y: CGFloat(translateY))
    // Same sum as padding + paddingHorizontal + paddingVertical; per-side keys win.
    .padding(padInsets)
    .frame(maxWidth: expandLayoutWidth ? .infinity : nil, maxHeight: expandLayoutHeight ? .infinity : nil)
    .background(containerBackground(
        bgColor: bgColor,
        borderRadius: borderRadius,
        perCornerRadiiSum: perCornerRadii,
        perCornerMax: perCornerMax,
        cornerMask: cornerMask,
        layoutWidth: adjustedWidth.map { CGFloat($0) },
        layoutHeight: adjustedHeight.map { CGFloat($0) }
    ))
    .overlay(borderOverlay(style, shape: borderShape))
    // Standard SwiftUI hit-testing fix for transparent areas in buttons/custom gestures.
    .contentShape(Rectangle())
    // For elements with clear background, ensure the frame itself is hit-testable.
    .background(Color.white.opacity(0.0001))
    // marginHorizontal/Vertical as before; per-side and margin keys win.
    .padding(marginInsets(style))
    .opacity(opacity)
}

// Same shape choice as containerBackground, for the border stroke.
@available(iOS 15.0, *)
private func containerShape(
    borderRadius: Double,
    perCornerRadiiSum: Double,
    perCornerMax: Double,
    cornerMask: ContainerCornerMask,
    layoutWidth: CGFloat?,
    layoutHeight: CGFloat?
) -> ErasedShape {
    let br = CGFloat(borderRadius)
    if borderRadius > 0,
       let w = layoutWidth, let h = layoutHeight,
       w > 0, h > 0, abs(w - h) < 0.5, br + 0.5 >= min(w, h) / 2 {
        return .circle
    } else if borderRadius > 0 {
        return .rounded(br)
    } else if perCornerRadiiSum > 0, perCornerMax > 0, !cornerMask.isEmpty {
        return .selective(CGFloat(perCornerMax), cornerMask)
    }
    return .rect
}

/// Uniform `borderRadius` (text/floating) vs per-corner keys (side tab from `getSpotCheckButtonStyles.js`).
@available(iOS 15.0, *)
@ViewBuilder
private func containerBackground(
    bgColor: Color,
    borderRadius: Double,
    perCornerRadiiSum: Double,
    perCornerMax: Double,
    cornerMask: ContainerCornerMask,
    layoutWidth: CGFloat? = nil,
    layoutHeight: CGFloat? = nil
) -> some View {
    let br = CGFloat(borderRadius)
    if borderRadius > 0,
       let w = layoutWidth, let h = layoutHeight,
       w > 0, h > 0, abs(w - h) < 0.5, br + 0.5 >= min(w, h) / 2 {
        bgColor.clipShape(Circle())
    } else if borderRadius > 0 {
        bgColor.clipShape(RoundedRectangle(cornerRadius: br, style: .continuous))
    } else if perCornerRadiiSum > 0, perCornerMax > 0, !cornerMask.isEmpty {
        bgColor.clipShape(SelectiveRoundedRectangle(radius: CGFloat(perCornerMax), corners: cornerMask))
    } else {
        bgColor
    }
}

/// A helper view that adjusts the layout frame for rotated content.
/// If rotation is ±90° or ±270°, it uses the measured size to swap height/width in the layout.
@available(iOS 15.0, *)
private struct RotatedLayout<Content: View>: View {
    let rotation: Double
    let width: Double?
    let height: Double?
    let alignment: Alignment
    @ViewBuilder let content: () -> Content

    @State private var intrinsicSize: CGSize = .zero

    private var isQuarterTurn: Bool {
        abs(abs(sin(rotation)) - 1.0) < 0.01
    }

    /// When rotation ≈ 0, avoid `ZStack` + `GeometryReader`: the ZStack is offered the overlay’s full height and
    /// centers the wrapper vertically (survey looks mid-screen) even when overlay `alignment` is `topCenter`.
    private var isIdentityRotation: Bool {
        abs(rotation) < 0.001
    }

    var body: some View {
        let frameW = isQuarterTurn ? (intrinsicSize.height > 0 ? intrinsicSize.height : nil) : (width.flatMap { CGFloat($0) })
        let frameH = isQuarterTurn ? (intrinsicSize.width > 0 ? intrinsicSize.width : nil) : (height.flatMap { CGFloat($0) })

        Group {
            if isIdentityRotation {
                content()
                    .rotationEffect(.radians(rotation))
                    .frame(width: frameW, height: frameH, alignment: alignment)
            } else {
                ZStack(alignment: alignment) {
                    Group {
                        if width == nil && height == nil {
                            content()
                                .fixedSize(horizontal: true, vertical: true)
                        } else {
                            content()
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.onAppear {
                                intrinsicSize = geo.size
                            }
                        }
                    )
                    .rotationEffect(.radians(rotation))
                }
                .frame(width: frameW, height: frameH, alignment: alignment)
            }
        }
        .clipped(false)
    }
}

/// Floating / pill frames: use a true circle when the style is square with a full corner radius so
/// `RoundedRectangle` never renders as a stadium/oval when layout rounds width vs height slightly apart.
@available(iOS 15.0, *)
@ViewBuilder
private func frameStyleBackgroundFill(
    bgColor: Color,
    width: CGFloat?,
    height: CGFloat?,
    borderRadius: CGFloat
) -> some View {
    if let w = width, let h = height, w > 0, h > 0, abs(w - h) < 0.5, borderRadius + 0.5 >= min(w, h) / 2 {
        Circle().fill(bgColor)
    } else if borderRadius > 0 {
        RoundedRectangle(cornerRadius: borderRadius, style: .continuous)
            .fill(bgColor)
    } else {
        bgColor
    }
}

@available(iOS 15.0, *)
extension View {
    @ViewBuilder
    fileprivate func frameStyleCornerClip(radius: CGFloat, corners: ContainerCornerMask) -> some View {
        if radius > 0 {
            clipShape(SelectiveRoundedRectangle(radius: radius, corners: corners))
        } else {
            self
        }
    }

    @ViewBuilder
    fileprivate func frameStyleContentClip(outerW: CGFloat?, outerH: CGFloat?, borderRadius: CGFloat, clipBehavior: String?) -> some View {
        if borderRadius > 0 {
            if let w = outerW, let h = outerH, w > 0, h > 0, abs(w - h) < 0.5, borderRadius + 0.5 >= min(w, h) / 2 {
                clipShape(Circle())
            } else {
                clipShape(RoundedRectangle(cornerRadius: borderRadius, style: .continuous))
            }
        } else if clipBehavior == "hardEdge" || clipBehavior == "antiAlias" {
            clipped()
        } else {
            self
        }
    }
}

@available(iOS 15.0, *)
func applyFrameStyle<Content: View>(_ style: [String: Any], @ViewBuilder content: () -> Content) -> some View {
    let width = toDoubleOpt(style["width"])
    let height = toDoubleOpt(style["height"])
    let opacity = toDoubleOpt(style["opacity"]) ?? 1.0
    let bgColor = parseColor(style["color"] as? String ?? style["backgroundColor"] as? String)
    let borderRadius = toDoubleOpt(style["borderRadius"]) ?? 0
    let clipBehavior = style["clipBehavior"] as? String
    // Per-corner radii (card/miniCard webview frame) from the backend.
    let tl = toDoubleOpt(style["borderRadiusTopLeft"]) ?? 0
    let tr = toDoubleOpt(style["borderRadiusTopRight"]) ?? 0
    let bl = toDoubleOpt(style["borderRadiusBottomLeft"]) ?? 0
    let br = toDoubleOpt(style["borderRadiusBottomRight"]) ?? 0
    let cornerMask = containerCornerMaskFromStyle(
        borderRadiusTopLeft: tl, borderRadiusTopRight: tr,
        borderRadiusBottomLeft: bl, borderRadiusBottomRight: br
    )
    let perCornerRadius = borderRadius > 0 ? 0 : CGFloat(max(tl, tr, bl, br))
    // New margin keys move all margins outside the background; else today's inner marginHorizontal.
    let hasNewMargin = styleHasAny(style, newMarginKeys + ["marginVertical"])
    let marginH = hasNewMargin ? 0 : (toDoubleOpt(style["marginHorizontal"]) ?? 0)
    let outerMargin = hasNewMargin ? marginInsets(style) : EdgeInsets()
    let pad = CGFloat(toDoubleOpt(style["padding"]) ?? 0)
    // Per-side/axis padding is new for Frame; zero when absent.
    let sidePad = EdgeInsets(
        top: CGFloat(styleNum(style, "paddingTop") ?? styleNum(style, "paddingVertical") ?? 0),
        leading: CGFloat(styleNum(style, "paddingLeft") ?? styleNum(style, "paddingHorizontal") ?? 0),
        bottom: CGFloat(styleNum(style, "paddingBottom") ?? styleNum(style, "paddingVertical") ?? 0),
        trailing: CGFloat(styleNum(style, "paddingRight") ?? styleNum(style, "paddingHorizontal") ?? 0)
    )

    var adjustedWidth = width
    var adjustedHeight = height
    let isAbsolute = styleUsesAbsoluteLayout(style)

    // In SwiftUI, zero-size frames block absolute child expansion
    if isAbsolute {
        if adjustedWidth == 0 { adjustedWidth = nil }
        if adjustedHeight == 0 { adjustedHeight = nil }
    }
    let expandW = (width ?? 0) < 0
    let expandH = (height ?? 0) < 0

    let outerW = adjustedWidth.flatMap { $0 < 0 ? nil : CGFloat($0) }
    let outerH = adjustedHeight.flatMap { $0 < 0 ? nil : CGFloat($0) }
    let zAlign = flexZAlignment(style, base: parseAlignment(styleString(style, key: "alignment") ?? "center"))
    // Border follows the same shape as the clip.
    let frameBorderShape: ErasedShape = {
        let r = CGFloat(borderRadius)
        if r > 0 {
            if let w = outerW, let h = outerH, w > 0, h > 0, abs(w - h) < 0.5, r + 0.5 >= min(w, h) / 2 {
                return .circle
            }
            return .rounded(r)
        }
        if perCornerRadius > 0 { return .selective(perCornerRadius, cornerMask) }
        return .rect
    }()

    // RN `padding` on Frame insets children (floating rings). Only when outer width/height are fixed.
    let useInnerPad = pad > 0 && outerW != nil && outerH != nil && !expandW && !expandH
    let innerW = useInnerPad ? max(0, (outerW ?? 0) - 2 * pad) : nil as CGFloat?
    let innerH = useInnerPad ? max(0, (outerH ?? 0) - 2 * pad) : nil as CGFloat?

    return ZStack(alignment: zAlign) {
        content()
    }
    .padding(sidePad)
    .frame(width: useInnerPad ? innerW : outerW, height: useInnerPad ? innerH : outerH)
    .padding(useInnerPad ? pad : 0)
    .frame(width: outerW, height: outerH)
    .frame(maxWidth: expandW ? .infinity : nil, maxHeight: expandH ? .infinity : nil)
    .overlay(borderOverlay(style, shape: frameBorderShape))
    .padding(.horizontal, CGFloat(marginH))
    .background {
        frameStyleBackgroundFill(
            bgColor: bgColor,
            width: outerW,
            height: outerH,
            borderRadius: CGFloat(borderRadius)
        )
    }
    .frameStyleContentClip(
        outerW: outerW,
        outerH: outerH,
        borderRadius: CGFloat(borderRadius),
        clipBehavior: clipBehavior
    )
    .frameStyleCornerClip(radius: perCornerRadius, corners: cornerMask)
    .padding(outerMargin)
    .opacity(opacity)
}

/// RN `marginVertical` / `marginTop` / `marginBottom` on Image — SwiftUI uses padding on the outer view.
private func imageMarginEdgeInsets(_ style: [String: Any]) -> EdgeInsets {
    let mv = toDoubleOpt(style["marginVertical"]) ?? 0
    let mt = toDoubleOpt(style["marginTop"]) ?? mv
    let mb = toDoubleOpt(style["marginBottom"]) ?? mv
    let ml = toDoubleOpt(style["marginLeft"]) ?? toDoubleOpt(style["marginHorizontal"]) ?? 0
    let mr = toDoubleOpt(style["marginRight"]) ?? toDoubleOpt(style["marginHorizontal"]) ?? 0
    return EdgeInsets(
        top: CGFloat(mt),
        leading: CGFloat(ml),
        bottom: CGFloat(mb),
        trailing: CGFloat(mr)
    )
}

@available(iOS 15.0, *)
@ViewBuilder
func buildImageView(props: [String: Any], style: [String: Any]) -> some View {
    let iconStyle = style.isEmpty ? (props["style"] as? [String: Any] ?? [:]) : style
    let margins = imageMarginEdgeInsets(iconStyle)

    if let systemName = iconStyle["systemName"] as? String {
        let fontSize = toDoubleOpt(iconStyle["fontSize"]) ?? 15
        let color = iconStyle["color"] as? String ?? "#000000"
        // rgb()/rgba() need parseColor; Color(hex:) keeps the old fallback for everything else.
        let iconColor = color.lowercased().hasPrefix("rgb") ? parseColor(color) : Color(hex: color)
        Image(systemName: systemName)
            .font(.system(size: CGFloat(fontSize)))
            .foregroundColor(iconColor)
            .padding(margins)
    } else if let source = props["source"] as? [String: Any], let uri = source["uri"] as? String, !uri.isEmpty {
        let w = toDoubleOpt(iconStyle["width"]) ?? 48
        let h = toDoubleOpt(iconStyle["height"]) ?? 48
        let radius = toDoubleOpt(iconStyle["borderRadius"]) ?? 0

        let imageBlock = AsyncImage(url: URL(string: uri)) { phase in
            switch phase {
            case .success(let image):
                if (iconStyle["contentMode"] as? String) == "fit" {
                    image.resizable().scaledToFit()
                } else {
                    image.resizable().scaledToFill()
                }
            default:
                Color.clear
            }
        }
        .frame(width: CGFloat(w), height: CGFloat(h))
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(radius)))
        .overlay(borderOverlay(iconStyle, shape: .roundedCircular(CGFloat(radius))))

        Group {
            if (iconStyle["alignSelf"] as? String)?.lowercased() == "flex-start" {
                imageBlock.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                imageBlock
            }
        }
        .padding(margins)
    } else {
        EmptyView()
    }
}

@available(iOS 15.0, *)
@ViewBuilder
func buildSvgXmlView(props: [String: Any], style: [String: Any]) -> some View {
    let xml = props["xml"] as? String ?? ""
    if xml.isEmpty {
        EmptyView()
    } else {
        let width = toDoubleOpt(props["width"]) ?? toDoubleOpt(style["width"]) ?? 20
        let height = toDoubleOpt(props["height"]) ?? toDoubleOpt(style["height"]) ?? 20
        InlineSVGView(svgXML: xml)
            .frame(width: CGFloat(width), height: CGFloat(height))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(toDoubleOpt(style["borderRadius"]) ?? 0)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

@available(iOS 15.0, *)
@ViewBuilder
func buildTextView(text: String, style: [String: Any]) -> some View {
    let fontSize = toDoubleOpt(style["fontSize"]) ?? 14
    let fontWeight = (style["fontWeight"] as? String) == "bold" ? Font.Weight.bold : Font.Weight.regular
    let color = style["color"] as? String ?? "#000000"
    let family = styleString(style, key: "fontFamily") ?? ""
    // Custom font only when installed; else today's system font.
    let font: Font = !family.isEmpty && UIFont(name: family, size: CGFloat(fontSize)) != nil
        ? (fontWeight == .bold ? Font.custom(family, size: CGFloat(fontSize)).weight(.bold) : Font.custom(family, size: CGFloat(fontSize)))
        : .system(size: CGFloat(fontSize), weight: fontWeight)
    let base = Text(text).font(font)
    let label = (styleString(style, key: "fontStyle")?.lowercased() == "italic") ? base.italic() : base

    label
        .foregroundColor(Color(hex: color))
}

/// Parses alpha from `0.25`, `25%`, etc. for `rgb` / `rgba` strings from backend `hexToRgba`.
private func parseColorAlphaComponent(_ s: String) -> Double {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasSuffix("%"), let p = Double(t.dropLast()) {
        return max(0, min(1, p / 100))
    }
    return max(0, min(1, Double(t) ?? 1))
}

@available(iOS 13.0, *)
func parseColor(_ colorStr: String?) -> Color {
    guard let raw = colorStr, !raw.isEmpty else { return .clear }
    let colorStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = colorStr.lowercased()

    if lower.hasPrefix("rgba("), colorStr.hasSuffix(")") {
        let inner = String(colorStr.dropFirst(5).dropLast())
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count >= 4 {
            let r = Double(parts[0]) ?? 0
            let g = Double(parts[1]) ?? 0
            let b = Double(parts[2]) ?? 0
            let a = parseColorAlphaComponent(String(parts[3]))
            return Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a)
        }
    }

    if lower.hasPrefix("rgb("), colorStr.hasSuffix(")") {
        let inner = String(colorStr.dropFirst(4).dropLast())
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count >= 3 {
            let r = Double(parts[0]) ?? 0
            let g = Double(parts[1]) ?? 0
            let b = Double(parts[2]) ?? 0
            let a = parts.count >= 4 ? parseColorAlphaComponent(String(parts[3])) : 1
            return Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a)
        }
    }

    if colorStr == "white" { return .white }
    if colorStr == "black" { return .black }
    if colorStr == "clear" || colorStr == "transparent" { return .clear }

    if colorStr.hasPrefix("#") {
        return Color(hex: colorStr)
    }

    return .clear
}

@available(iOS 13.0, *)
func parseAlignment(_ str: String?) -> Alignment {
    switch str {
    case "center": return .center
    case "topCenter": return .top
    case "bottomCenter": return .bottom
    case "topLeading": return .topLeading
    case "topTrailing": return .topTrailing
    case "bottomLeading": return .bottomLeading
    case "bottomTrailing": return .bottomTrailing
    default: return .center
    }
}

// MARK: - View Extension for clipped

@available(iOS 13.0, *)
extension View {
    @ViewBuilder
    func clipped(_ shouldClip: Bool) -> some View {
        if shouldClip {
            self.clipped()
        } else {
            self
        }
    }
}

@available(iOS 15.0, *)
struct InlineSVGView: UIViewRepresentable {
    let svgXML: String

    // Tracks the loaded markup so SwiftUI updates don't reload (and blank) the icon.
    final class Coordinator {
        var loadedXML: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        webView.loadHTMLString(html(for: svgXML), baseURL: nil)
        context.coordinator.loadedXML = svgXML
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.loadedXML != svgXML else { return }
        context.coordinator.loadedXML = svgXML
        uiView.loadHTMLString(html(for: svgXML), baseURL: nil)
    }

    private func html(for svg: String) -> String {
        """
        <html>
          <head>
            <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
            <style>
              html, body {
                margin: 0;
                padding: 0;
                width: 100%;
                height: 100%;
                overflow: hidden;
                background: transparent;
              }
              svg {
                display: block;
                width: 100%;
                height: 100%;
              }
            </style>
          </head>
          <body>
            \(svg)
          </body>
        </html>
        """
    }
}
