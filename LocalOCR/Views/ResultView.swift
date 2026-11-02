import SwiftUI

/// The page with line boxes on top, and the recognised text below.
struct ResultView: View {
    let result: PageResult
    @State private var selected: Int?
    @State private var copied = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                page
                    .frame(height: geo.size.height * 0.5)
                Divider()
                HStack {
                    Text(String(localized: "result_summary",
                                defaultValue: "\(result.engine.title)・\(result.lines.count) 行・\(String(format: "%.1f", result.seconds)) 秒"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = result.text
                        copied = true
                    } label: {
                        Label(copied ? String(localized: "copied", defaultValue: "コピーしました")
                                     : String(localized: "copy", defaultValue: "コピー"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .font(.caption)
                }
                .padding(.horizontal).padding(.vertical, 6)
                lines
            }
        }
    }

    private var page: some View {
        let w = CGFloat(result.image.width), h = CGFloat(result.image.height)
        return Image(decorative: result.image, scale: 1)
            .resizable().scaledToFit()
            .overlay {
                GeometryReader { g in
                    let sx = g.size.width / w, sy = g.size.height / h
                    ForEach(Array(result.lines.enumerated()), id: \.offset) { i, line in
                        let b = line.box
                        if b.count >= 4 {
                            Rectangle()
                                .stroke(i == selected ? Color.orange : Color.accentColor.opacity(0.8),
                                        lineWidth: i == selected ? 2.5 : 1)
                                .background(i == selected ? Color.orange.opacity(0.15) : .clear)
                                .frame(width: CGFloat(b[2] - b[0]) * sx, height: CGFloat(b[3] - b[1]) * sy)
                                .position(x: CGFloat(b[0] + b[2]) / 2 * sx, y: CGFloat(b[1] + b[3]) / 2 * sy)
                                .onTapGesture { selected = i }
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
    }

    private var lines: some View {
        ScrollViewReader { proxy in
            List(Array(result.lines.enumerated()), id: \.offset) { i, line in
                Text(line.text.isEmpty ? "—" : line.text)
                    .textSelection(.enabled)
                    .listRowBackground(i == selected ? Color.orange.opacity(0.15) : nil)
                    .id(i)
                    .onTapGesture { selected = i }
            }
            .listStyle(.plain)
            .onChange(of: selected) { _, i in
                if let i { withAnimation { proxy.scrollTo(i, anchor: .center) } }
            }
        }
    }
}
