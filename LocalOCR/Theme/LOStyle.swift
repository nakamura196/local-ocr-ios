import SwiftUI
import UIKit

// MARK: - Design system (sister of KotenOCR's KotenStyle)
//
// Same washi paper, Mincho type and Liquid Glass controls as KotenOCR, so the two apps read as a pair.
// The accent is 藍 (indigo) instead of 朱, and the seal says 読, so they are told apart on the home screen.
// Every `#available(iOS 26, *)` check for the design lives in this file.

private extension Color {
    init(light: (Double, Double, Double), dark: (Double, Double, Double)) {
        self.init(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

enum LOColor {
    static let washi = Color(light: (0.953, 0.922, 0.863), dark: (0.114, 0.102, 0.090))
    static let washiCard = Color(light: (0.984, 0.965, 0.925), dark: (0.165, 0.149, 0.133))
    static let ink = Color(light: (0.169, 0.149, 0.133), dark: (0.945, 0.902, 0.824))
    static let inkSecondary = Color(light: (0.420, 0.373, 0.322), dark: (0.737, 0.682, 0.596))
    /// 藍 for text, strokes and marks. Brighter in dark mode so it stays legible.
    static let ai = Color(light: (0.149, 0.302, 0.502), dark: (0.525, 0.671, 0.878))
    /// 藍 behind white text (buttons, stamps). Dark enough for 4.5:1 with white.
    static let aiFill = Color(light: (0.149, 0.302, 0.502), dark: (0.212, 0.380, 0.612))
    static let mount = Color(light: (0.910, 0.863, 0.776), dark: (0.208, 0.188, 0.165))
    static let rule = Color(light: (0.796, 0.722, 0.612), dark: (0.302, 0.275, 0.239))
    static let ok = Color(light: (0.180, 0.490, 0.255), dark: (0.400, 0.741, 0.471))
    static let danger = Color(light: (0.710, 0.271, 0.184), dark: (0.878, 0.408, 0.298))
    /// 藍 that reads on a live camera image (the frame corners). Same in light and dark.
    static let aiBright = Color(red: 0.525, green: 0.671, blue: 0.878)
    /// Dark board behind the photo in the crop screen, so the white crop frame reads clearly.
    static let docBackground = Color(red: 0.114, green: 0.106, blue: 0.098)

    /// Line boxes take these in turn so neighbouring lines never share a colour:
    /// 藍, 朱, 萌黄 (deep), 江戸紫. All four read on cream paper and on dark photos.
    static let boxPalette: [Color] = [
        Color(red: 0.13, green: 0.38, blue: 0.75),
        Color(red: 0.86, green: 0.27, blue: 0.16),
        Color(red: 0.16, green: 0.56, blue: 0.27),
        Color(red: 0.55, green: 0.27, blue: 0.62),
    ]

    static func box(_ index: Int) -> Color {
        boxPalette[((index % boxPalette.count) + boxPalette.count) % boxPalette.count]
    }
}

// MARK: - Type

extension Font {
    /// Hiragino Mincho, scaled with Dynamic Type relative to `style`.
    static func mincho(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, bold: Bool = false) -> Font {
        .custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size, relativeTo: style)
    }
}

// MARK: - Paper

struct WashiBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LOColor.washi
            RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.04 : 0.6), .clear],
                           center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 0.27, green: 0.38, blue: 0.55).opacity(scheme == .dark ? 0.10 : 0.10), .clear],
                           center: UnitPoint(x: 0.9, y: 0.9), startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func washiBackground() -> some View { background(WashiBackground()) }

    /// Document mount: the image sits on a darker paper board with a thin rule.
    func paperMount(padding: CGFloat = 8) -> some View {
        self
            .padding(padding)
            .background(LOColor.mount)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(LOColor.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color(red: 0.31, green: 0.24, blue: 0.12).opacity(0.15), radius: 8, y: 6)
    }

    /// Paper card: cream fill with a ruled edge.
    func paperCard(cornerRadius: CGFloat = 16, stroke: Color = LOColor.rule, lineWidth: CGFloat = 1.5) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(LOColor.washiCard))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(stroke, lineWidth: lineWidth))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass

enum LOGlassKind {
    /// Neutral control on paper (back, share, toolbars).
    case regular
    /// The one main action on a screen (Read, Copy). 藍.
    case prominent
    /// Control on top of the camera image.
    case onCamera
}

private struct LOGlassModifier<S: Shape>: ViewModifier {
    let kind: LOGlassKind
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(fallback)
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        var g: Glass = .regular
        if kind == .prominent { g = g.tint(LOColor.aiFill) }
        if interactive { g = g.interactive() }
        return g
    }

    @ViewBuilder private var fallback: some View {
        switch kind {
        case .regular:
            shape.fill(LOColor.washiCard)
                .overlay(shape.stroke(LOColor.rule, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        case .prominent:
            shape.fill(LOColor.aiFill)
        case .onCamera:
            shape.fill(Color(red: 0.17, green: 0.165, blue: 0.157))
                .overlay(shape.stroke(Color(red: 0.24, green: 0.23, blue: 0.215), lineWidth: 1))
        }
    }
}

extension View {
    func loGlass<S: Shape>(_ kind: LOGlassKind = .regular, in shape: S, interactive: Bool = false) -> some View {
        modifier(LOGlassModifier(kind: kind, shape: shape, interactive: interactive))
    }
}

struct LOGlassButtonStyle<S: Shape>: ButtonStyle {
    var kind: LOGlassKind = .regular
    var shape: S
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(kind == .regular ? LOColor.ink : .white)
            .contentShape(shape)
            .loGlass(kind, in: shape, interactive: true)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LOGlassButtonStyle<Capsule> {
    static var loGlass: LOGlassButtonStyle<Capsule> { .init(kind: .regular, shape: Capsule()) }
    static var loProminent: LOGlassButtonStyle<Capsule> { .init(kind: .prominent, shape: Capsule()) }
    static var loCamera: LOGlassButtonStyle<Capsule> { .init(kind: .onCamera, shape: Capsule()) }
}

extension ButtonStyle where Self == LOGlassButtonStyle<Circle> {
    static var loGlassCircle: LOGlassButtonStyle<Circle> { .init(kind: .regular, shape: Circle()) }
    static var loCameraCircle: LOGlassButtonStyle<Circle> { .init(kind: .onCamera, shape: Circle()) }
}

/// Paper card button. Shrinks to 0.96 when pressed.
struct PaperCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Labels

struct BackLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left").font(.body.weight(.semibold))
            Text(title).font(.body.weight(.bold)).lineLimit(1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(minHeight: 44)
    }
}

struct IconLabel: View {
    let systemName: String
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .frame(width: size, height: size)
    }
}

// MARK: - Seal (藍印)

/// The 読 seal used in the header and empty states.
struct LOSeal: View {
    var size: CGFloat = 40
    var rotation: Double = -2

    var body: some View {
        let border = max(2, size * 0.06)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1).fill(LOColor.washi)
            RoundedRectangle(cornerRadius: size * 0.1).strokeBorder(LOColor.ai, lineWidth: border)
            RoundedRectangle(cornerRadius: size * 0.06)
                .strokeBorder(LOColor.ai, lineWidth: max(1, border * 0.4))
                .padding(border * 1.6)
            Text("読")
                .font(.custom("HiraMinProN-W6", fixedSize: size * 0.6))
                .foregroundColor(LOColor.ai)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

enum LOMotion {
    static func spring(_ response: Double = 0.4, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: response, dampingFraction: 0.86)
    }

    static func rise(_ distance: CGFloat = 16, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: distance).combined(with: .opacity)
    }
}

enum LOHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Engine presentation

extension EngineKind {
    var symbol: String {
        switch self {
        case .vision: return "text.viewfinder"
        case .ndlKoten: return "scroll"
        case .ndlModern: return "book.closed"
        case .ppocr: return "globe"
        }
    }

    /// Two or three words for the engine card.
    var tag: String {
        switch self {
        case .vision: return String(localized: "engine_vision_tag", defaultValue: "現代の活字・手書き")
        case .ndlKoten: return String(localized: "engine_koten_tag", defaultValue: "くずし字・版本")
        case .ndlModern: return String(localized: "engine_ndl_tag", defaultValue: "明治以降の活字")
        case .ppocr: return String(localized: "engine_ppocr_tag", defaultValue: "多言語の活字")
        }
    }
}
