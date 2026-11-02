import SwiftUI

/// The download screen: one row per engine, with its size, licence, and download / delete.
struct ModelsView: View {
    @EnvironmentObject var store: ModelStore
    @EnvironmentObject var recognizer: Recognizer
    @State private var confirmDelete: EngineKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "models_lead",
                            defaultValue: "資料に合うモデルを入れてください。最初に一度だけダウンロードし、そのあとはすべてこの端末の中で読み取ります。"))
                    .font(.mincho(15, relativeTo: .subheadline))
                    .foregroundColor(LOColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                ForEach(EngineKind.allCases) { kind in
                    EngineRow(kind: kind, status: store.status[kind] ?? .notInstalled,
                              onDownload: { store.download(kind) },
                              onCancel: { store.cancel(kind) },
                              onDelete: { confirmDelete = kind })
                }

                HStack {
                    Image(systemName: "internaldrive")
                    Text(String(localized: "models_used", defaultValue: "使っている容量"))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: store.usedBytes, countStyle: .file))
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundColor(LOColor.ink)
                .padding(16)
                .paperCard(cornerRadius: 14, lineWidth: 1)

                Label(String(localized: "models_footer",
                             defaultValue: "画像も結果も外に送りません。Wi-Fi でのダウンロードをお勧めします。"),
                      systemImage: "wifi")
                    .font(.footnote)
                    .foregroundColor(LOColor.inkSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .washiBackground()
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 22))
                    .foregroundColor(LOColor.ai)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LOColor.ai.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.mincho(17, relativeTo: .headline, bold: true))
                    Text(kind.tag).font(.caption).foregroundColor(LOColor.inkSecondary)
                }
                Spacer()
                Text(sizeLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(LOColor.inkSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().stroke(LOColor.rule, lineWidth: 1))
            }
            Text(kind.summary)
                .font(.subheadline)
                .foregroundColor(LOColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(kind.license).font(.caption2).foregroundColor(LOColor.inkSecondary)
            controls
        }
        .padding(16)
        .paperCard(cornerRadius: 16,
                   stroke: status == .installed ? LOColor.ai.opacity(0.5) : LOColor.rule,
                   lineWidth: 1)
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
                    .foregroundStyle(LOColor.ok)
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
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.loProminent)
        case .downloading(let p):
            HStack {
                ProgressView(value: p).tint(LOColor.ai)
                Text("\(Int(p * 100))%").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                Button(String(localized: "models_cancel", defaultValue: "中止"), action: onCancel)
                    .buttonStyle(.borderless)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.caption).foregroundStyle(LOColor.danger)
                Button(action: onDownload) {
                    Label(String(localized: "models_retry", defaultValue: "やり直す"), systemImage: "arrow.clockwise")
                        .font(.body.weight(.bold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.loGlass)
            }
        }
    }
}
