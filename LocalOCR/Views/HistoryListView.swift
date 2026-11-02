import SwiftUI

/// Pages read before, newest first. Ported from KotenOCR's HistoryListView; also shows the engine.
struct HistoryListView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAllConfirm = false
    @State private var itemToDelete: HistoryItem?
    var onSelect: (HistoryItem) -> Void
    /// Shown as the main button on the empty state.
    var onStartCamera: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if historyManager.items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(historyManager.items) { item in
                            HStack(spacing: 8) {
                                Button {
                                    onSelect(item)
                                    dismiss()
                                } label: {
                                    row(item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(Self.accessibilityLabel(for: item)))

                                Button {
                                    itemToDelete = item
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                        .foregroundColor(LOColor.danger)
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text(String(localized: "history_delete_item", defaultValue: "この履歴を削除")))
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(LOColor.washiCard)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                historyManager.delete(item: historyManager.items[index])
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .washiBackground()
            .tint(LOColor.ai)
            .accessibilityIdentifier("history_list")
            .navigationTitle(String(localized: "history_title", defaultValue: "履歴"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !historyManager.items.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Text(String(localized: "history_delete_all", defaultValue: "すべて削除"))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(LOColor.ink)
                    }
                    .accessibilityLabel(Text(String(localized: "close", defaultValue: "閉じる")))
                }
            }
        }
        .confirmationDialog(
            String(localized: "history_delete_item_title", defaultValue: "この履歴を削除しますか？"),
            isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "history_delete_item", defaultValue: "この履歴を削除"), role: .destructive) {
                if let item = itemToDelete { historyManager.delete(item: item) }
                itemToDelete = nil
            }
            Button(String(localized: "cancel", defaultValue: "キャンセル"), role: .cancel) { itemToDelete = nil }
        }
        .alert(String(localized: "history_delete_all_title", defaultValue: "すべての履歴を削除"),
               isPresented: $showDeleteAllConfirm) {
            Button(String(localized: "history_delete_all", defaultValue: "すべて削除"), role: .destructive) {
                historyManager.deleteAll()
            }
            Button(String(localized: "cancel", defaultValue: "キャンセル"), role: .cancel) {}
        } message: {
            Text(String(localized: "history_delete_all_message", defaultValue: "すべての読み取りの履歴を削除しますか？この操作は元に戻せません。"))
        }
    }

    private func row(_ item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            HistoryThumbnailView(item: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text.prefix(50).replacingOccurrences(of: "\n", with: " "))
                    .font(.mincho(16, relativeTo: .subheadline))
                    .foregroundColor(LOColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.date, style: .date)
                    .font(.caption)
                    .foregroundColor(LOColor.inkSecondary)
                HStack(spacing: 6) {
                    if let kind = item.engineKind {
                        Label(kind.title, systemImage: kind.symbol)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    Text(String(format: String(localized: "lines_count_format", defaultValue: "%d 行"), item.detections.count))
                }
                .font(.caption2)
                .foregroundColor(LOColor.inkSecondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    /// The 読 seal inside an open brush circle, and one main action.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                EmptyHistoryIllustration()
                    .frame(width: 170, height: 170)
                    .padding(.top, 80)
                Text(String(localized: "history_empty_title", defaultValue: "まだ記録はありません"))
                    .font(.mincho(24, relativeTo: .title2, bold: true))
                    .foregroundColor(LOColor.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)
                    .accessibilityIdentifier("history_empty")
                Text(String(localized: "history_empty_body", defaultValue: "読み取った資料はここに残ります。"))
                    .font(.body)
                    .foregroundColor(LOColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if let onStartCamera, UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    dismiss()
                    onStartCamera()
                } label: {
                    Text(String(localized: "home_take_photo", defaultValue: "撮影して読む"))
                        .font(.mincho(19, relativeTo: .headline, bold: true))
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.loProminent)
                .accessibilityIdentifier("history_empty_camera_button")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    /// "<label>, <date>, <first line of text>" so VoiceOver users can tell rows apart.
    static func accessibilityLabel(for item: HistoryItem, locale: Locale = .current) -> String {
        let date = item.date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
        let firstLine = item.text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(50)) } ?? ""
        let base = String(localized: "history_item_label", defaultValue: "読み取り結果")
        return [base, date, firstLine].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Brush circle drawn as an open, slightly uneven stroke, with the small 読 seal.
private struct EmptyHistoryIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 200
            ZStack(alignment: .topLeading) {
                EnsoShape()
                    .stroke(LOColor.ink.opacity(0.85),
                            style: StrokeStyle(lineWidth: 13 * s, lineCap: .round, lineJoin: .round))
                LOSeal(size: 44 * s, rotation: 1)
                    .offset(x: 118 * s, y: 130 * s)
            }
            .frame(width: 200 * s, height: 200 * s)
        }
        .accessibilityHidden(true)
    }
}

/// The 円相 path (viewBox 200×200), not quite closed. Same as KotenOCR.
private struct EnsoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 200
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var p = Path()
        p.move(to: pt(100, 22))
        p.addCurve(to: pt(178, 104), control1: pt(150, 20), control2: pt(182, 58))
        p.addCurve(to: pt(92, 178), control1: pt(174, 152), control2: pt(136, 182))
        p.addCurve(to: pt(24, 94), control1: pt(46, 174), control2: pt(20, 138))
        p.addCurve(to: pt(96, 24), control1: pt(27, 58), control2: pt(52, 30))
        return p
    }
}

/// Loads the downsampled thumbnail off the main thread.
private struct HistoryThumbnailView: View {
    let item: HistoryItem
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .cornerRadius(8)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LOColor.mount)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "doc.text")
                            .foregroundColor(LOColor.inkSecondary)
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: item.id) {
            image = await HistoryManager.shared.thumbnail(for: item)
        }
    }
}

/// Recent page on the home screen: thumbnail with date and line count. Same as KotenOCR's.
struct RecentThumbnail: View {
    let item: HistoryItem
    var height: CGFloat = 112
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LOColor.mount
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(LOColor.rule, lineWidth: 1))

            Text(caption)
                .font(.caption)
                .foregroundColor(LOColor.inkSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity)
        .task(id: "\(item.id)-\(height)") {
            image = height > 112
                ? await HistoryManager.shared.preview(for: item, maxPixel: height * 3)
                : await HistoryManager.shared.thumbnail(for: item)
        }
    }

    private var caption: String {
        let date = item.date.formatted(.dateTime.month(.defaultDigits).day())
        let lines = String(format: String(localized: "lines_count_format", defaultValue: "%d 行"), item.detections.count)
        return "\(date)  \(lines)"
    }
}
