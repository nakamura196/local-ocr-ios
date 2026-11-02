import SwiftUI

// Camera frame corners and one-time hints, from KotenOCR (KotenStyle.swift). 藍 instead of 朱.

/// Four rounded scan-frame corners.
struct ScanCorners: Shape {
    var inset: CGFloat = 0
    var length: CGFloat = 34
    var radius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let l = min(length, r.width / 2, r.height / 2)
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // top-right
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // bottom-left
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

// MARK: - One-time coach marks

enum CoachMark: String, CaseIterable {
    case shutter = "coachShutterShown"
    case cropCorner = "coachCropCornerShown"

    var isShown: Bool { UserDefaults.standard.bool(forKey: rawValue) }

    func markShown() { UserDefaults.standard.set(true, forKey: rawValue) }

    static func resetAll() {
        allCases.forEach { UserDefaults.standard.removeObject(forKey: $0.rawValue) }
    }
}

/// Speech bubble with a 藍 border and a pointer. Mincho text, since it is guidance content.
struct CoachBubble: View {
    enum Pointer { case up, down }
    let text: String
    var pointer: Pointer = .down
    /// Horizontal position of the pointer, 0...1.
    var pointerX: CGFloat = 0.5

    var body: some View {
        Text(text)
            .font(.mincho(18, relativeTo: .headline, bold: true))
            .foregroundColor(LOColor.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                BubbleShape(pointer: pointer, pointerX: pointerX)
                    .fill(LOColor.washiCard)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            )
            .overlay(BubbleShape(pointer: pointer, pointerX: pointerX).stroke(LOColor.ai, lineWidth: 3))
            .padding(pointer == .down ? .bottom : .top, 12)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct BubbleShape: Shape {
    let pointer: CoachBubble.Pointer
    let pointerX: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tip: CGFloat = 12
        let x = min(max(rect.minX + radius + tip, rect.minX + rect.width * pointerX), rect.maxX - radius - tip)
        var p = Path()
        // Clockwise outline from the top-left corner, with the pointer drawn into the edge.
        p.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        if pointer == .up {
            p.addLine(to: CGPoint(x: x - tip, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.minY - tip))
            p.addLine(to: CGPoint(x: x + tip, y: rect.minY))
        }
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        if pointer == .down {
            p.addLine(to: CGPoint(x: x + tip, y: rect.maxY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY + tip))
            p.addLine(to: CGPoint(x: x - tip, y: rect.maxY))
        }
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
