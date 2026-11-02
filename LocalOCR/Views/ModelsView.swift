import SwiftUI

/// The download screen: one row per engine, with its size, licence, and download / delete.
struct ModelsView: View {
    @EnvironmentObject var store: ModelStore
    @EnvironmentObject var recognizer: Recognizer
    @State private var confirmDelete: EngineKind?

    var body: some View {
        List {
            Section {
                ForEach(EngineKind.allCases) { kind in
                    EngineRow(kind: kind, status: store.status[kind] ?? .notInstalled,
                              onDownload: { store.download(kind) },
                              onCancel: { store.cancel(kind) },
                              onDelete: { confirmDelete = kind })
                }
            } footer: {
                Text(String(localized: "models_footer",
                            defaultValue: "モデルは最初に一度だけダウンロードします。そのあとの読み取りは、すべてこの端末の中で行い、画像も結果も外に送りません。Wi-Fi でのダウンロードをお勧めします。"))
            }
            Section {
                LabeledContent(String(localized: "models_used", defaultValue: "使っている容量"),
                               value: ByteCountFormatter.string(fromByteCount: store.usedBytes, countStyle: .file))
            }
        }
        .navigationTitle(String(localized: "models_title", defaultValue: "読み取りモデル"))
        .onAppear { store.refresh() }
        .confirmationDialog(
            String(localized: "models_delete_title", defaultValue: "モデルを削除しますか？"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible,
            presenting: confirmDelete
        ) { kind in
            Button(String(localized: "models_delete", defaultValue: "削除"), role: .destructive) {
                recognizer.unload(kind)
                store.delete(kind)
            }
        } message: { kind in
            Text(String(localized: "models_delete_message",
                        defaultValue: "\(kind.title) を使うには、もう一度ダウンロードが必要になります。"))
        }
    }
}

private struct EngineRow: View {
    let kind: EngineKind
    let status: ModelStore.Status
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title).font(.headline)
                Spacer()
                Text(sizeLabel).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(kind.summary).font(.subheadline)
            Text(kind.license).font(.caption).foregroundStyle(.secondary)
            controls
        }
        .padding(.vertical, 4)
    }

    private var sizeLabel: String {
        kind.needsDownload
            ? ByteCountFormatter.string(fromByteCount: kind.downloadSize, countStyle: .file)
            : String(localized: "models_builtin", defaultValue: "内蔵")
    }

    @ViewBuilder private var controls: some View {
        switch status {
        case .installed:
            HStack {
                Label(String(localized: "models_ready", defaultValue: "使えます"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                if kind.needsDownload {
                    Button(String(localized: "models_delete", defaultValue: "削除"), role: .destructive, action: onDelete)
                        .buttonStyle(.borderless)
                }
            }
            .font(.subheadline)
        case .notInstalled:
            Button(action: onDownload) {
                Label(String(localized: "models_download", defaultValue: "ダウンロード"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
        case .downloading(let p):
            HStack {
                ProgressView(value: p)
                Text("\(Int(p * 100))%").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                Button(String(localized: "models_cancel", defaultValue: "中止"), action: onCancel)
                    .buttonStyle(.borderless)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.caption).foregroundStyle(.red)
                Button(action: onDownload) {
                    Label(String(localized: "models_retry", defaultValue: "やり直す"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
