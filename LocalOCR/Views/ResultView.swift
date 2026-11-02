import SwiftUI

/// The page with coloured line boxes on top, and the recognised lines below.
/// A line and its box share a colour; tapping either highlights both.
struct ResultView: View {
    let result: PageResult
    /// "履歴" when opened from History; nil shows "戻る" (back to the page to read it again).
    var backTitle: String? = nil
    let onBack: () -> Void
    let onNew: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Int?
    @State private var copied = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                page
                    .frame(maxHeight: geo.size.height * 0.42)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                summary
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                lines
            }
            .overlay(alignment: .bottom) { bottomBar }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                BackLabel(title: backTitle ?? String(localized: "back", defaultValue: "戻る"))
            }
            .buttonStyle(.loGlass)
            .accessibilityHint(backTitle == nil
                               ? Text(String(localized: "back_to_page_hint", defaultValue: "別の方式で読み直せます"))
                               : Text(""))
            Spacer()
            ShareLink(item: result.text) {
                IconLabel(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.loGlassCircle)
            .accessibilityLabel(Text(String(localized: "share", defaultValue: "共有")))
        }
    }

    // MARK: Page

    private var page: some View {
        let w = CGFloat(result.image.width), h = CGFloat(result.image.height)
        return Image(decorative: result.image, scale: 1)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { g in
                    let sx = g.size.width / w, sy = g.size.height / h
                    ForEach(Array(result.lines.enumerated()), id: \.offset) { i, line in
                        let b = line.box
                        if b.count >= 4 {
                            let color = LOColor.box(i)
                            let on = i == selected
                            Rectangle()
                                .fill(color.opacity(on ? 0.28 : 0.08))
                                .overlay(Rectangle().stroke(color, lineWidth: on ? 2.5 : 1.2))
                                .frame(width: CGFloat(b[2] - b[0]) * sx, height: CGFloat(b[3] - b[1]) * sy)
                                .position(x: CGFloat(b[0] + b[2]) / 2 * sx, y: CGFloat(b[1] + b[3]) / 2 * sy)
                                .onTapGesture { select(i) }
                        }
                    }
                }
            }
            .paperMount()
            .frame(maxWidth: .infinity)
    }

    // MARK: Summary

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(result.engine.title, systemImage: result.engine.symbol)
                .font(.mincho(15, relativeTo: .subheadline, bold: true))
                .foregroundColor(LOColor.ink)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 4)
            stat(String(localized: "result_lines", defaultValue: "\(result.lines.count) 行"))
            stat(String(localized: "result_chars", defaultValue: "\(result.text.count) 字"))
            stat(String(format: String(localized: "result_seconds", defaultValue: "%.1f 秒"), result.seconds))
        }
        .overlay(alignment: .bottom) { LOColor.rule.frame(height: 1).offset(y: 8) }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundColor(LOColor.inkSecondary)
    }

    // MARK: Lines

    private var lines: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if result.lines.isEmpty {
                        Text(String(localized: "result_empty", defaultValue: "文字が見つかりませんでした。別の方式で読み直すと読めることがあります。"))
                            .font(.mincho(16))
                            .foregroundColor(LOColor.inkSecondary)
                            .padding(24)
                    }
                    ForEach(Array(result.lines.enumerated()), id: \.offset) { i, line in
                        LineRow(index: i, text: line.text, selected: i == selected)
                            .id(i)
                            .onTapGesture { select(i) }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .onChange(of: selected) { _, i in
                if let i { withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) { proxy.scrollTo(i, anchor: .center) } }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: onNew) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(String(localized: "new_image", defaultValue: "次の画像"))
                        .font(.body.weight(.bold))
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
            }
            .buttonStyle(.loGlass)

            Button {
                UIPasteboard.general.string = result.text
                LOHaptics.notify(.success)
                withAnimation(.easeOut(duration: 0.2)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? String(localized: "copied", defaultValue: "コピーしました")
                                : String(localized: "copy_all", defaultValue: "全文をコピー"))
                        .font(.mincho(18, relativeTo: .headline, bold: true))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.loProminent)
            .disabled(result.lines.isEmpty)
            .accessibilityIdentifier("copy_button")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .background(
            LinearGradient(stops: [.init(color: LOColor.washi.opacity(0), location: 0),
                                   .init(color: LOColor.washi, location: 0.4),
                                   .init(color: LOColor.washi, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }

    private func select(_ i: Int) {
        LOHaptics.impact(.light)
        withAnimation(.easeOut(duration: 0.15)) { selected = (selected == i) ? nil : i }
    }
}

/// One recognised line: a coloured number (matching its box) and the text in Mincho.
private struct LineRow: View {
    let index: Int
    let text: String
    let selected: Bool

    var body: some View {
        let color = LOColor.box(index)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundColor(color)
                .frame(minWidth: 22, alignment: .trailing)
                .accessibilityHidden(true)
            Text(text.isEmpty ? "—" : text)
                .font(.mincho(17))
                .foregroundColor(LOColor.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(
            Rectangle()
                .fill(color.opacity(selected ? 0.14 : 0))
                .overlay(alignment: .leading) { color.frame(width: selected ? 3 : 0) }
        )
        .overlay(alignment: .bottom) { LOColor.rule.opacity(0.5).frame(height: 0.5).padding(.leading, 54) }
        .contentShape(Rectangle())
    }
}
