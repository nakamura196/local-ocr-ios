import SwiftUI
import ImageIO

/// A page bundled with the app, so the reader can try OCR without a book at hand.
/// The five pages and their credits are the same as KotenOCR's.
struct SamplePage: Identifiable {
    let id: String
    let title: String
    let credit: String
    let engine: EngineKind

    static var all: [SamplePage] {
        let ndl = String(localized: "sample_ndl_credit", defaultValue: "国立国会図書館デジタルコレクション")
        return [
            SamplePage(id: "sample_taketori",
                       title: String(localized: "sample_taketori_title", defaultValue: "竹取物語"),
                       credit: ndl, engine: .ndlKoten),
            SamplePage(id: "sample_genji",
                       title: String(localized: "sample_genji_title", defaultValue: "源氏物語　桐壺"),
                       credit: String(localized: "sample_genji_credit", defaultValue: "『源氏物語』（東京大学総合図書館所蔵）を改変"),
                       engine: .ndlKoten),
            SamplePage(id: "sample_kikuchi",
                       title: String(localized: "sample_kikuchi_title", defaultValue: "菊池武光 施行状（古文書）"),
                       credit: String(localized: "sample_kikuchi_credit", defaultValue: "『古文書時代鑑』（国立国会図書館デジタルコレクション）"),
                       engine: .ndlKoten),
            SamplePage(id: "sample_shibata",
                       title: String(localized: "sample_shibata_title", defaultValue: "柴田太郎吉 明細書（斜めに撮った写真）"),
                       credit: String(localized: "sample_shibata_credit", defaultValue: "写真: 柴田バネッサ（CC BY-SA 4.0）"),
                       engine: .ndlKoten),
            SamplePage(id: "sample_modern",
                       title: String(localized: "sample_modern_title", defaultValue: "国立国会図書館スタッフ・マニュアル"),
                       credit: ndl, engine: .ndlModern),
        ]
    }

    var url: URL? { Bundle.main.url(forResource: id, withExtension: "jpg") }

    func loadImage() -> UIImage? {
        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

/// Lists the bundled sample pages; choosing one reads it with that page's engine.
struct SampleSheet: View {
    @EnvironmentObject var store: ModelStore
    var onSelect: (SamplePage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "sample_sheet_lead", defaultValue: "選ぶとすぐに読み取ります。"))
                        .font(.subheadline)
                        .foregroundColor(LOColor.inkSecondary)
                        .padding(.horizontal, 4)
                    ForEach(Array(SamplePage.all.enumerated()), id: \.element.id) { index, page in
                        Button {
                            dismiss()
                            onSelect(page)
                        } label: {
                            SampleRow(page: page, installed: store.status[page.engine] == .installed)
                        }
                        .buttonStyle(PaperCardButtonStyle())
                        .accessibilityIdentifier("sample_\(index)")
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .washiBackground()
            .navigationTitle(Text(String(localized: "sample_sheet_title", defaultValue: "サンプルで試す")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel", defaultValue: "キャンセル")) { dismiss() }
                }
            }
        }
    }
}

private struct SampleRow: View {
    let page: SamplePage
    let installed: Bool
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            LOColor.mount
                .frame(width: 84, height: 84)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(LOColor.rule, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.mincho(17, relativeTo: .headline, bold: true))
                    .foregroundColor(LOColor.ink)
                HStack(spacing: 6) {
                    Text(page.engine.title)
                        .foregroundColor(LOColor.ai)
                    if !installed {
                        Text(String(localized: "sample_needs_download", defaultValue: "要ダウンロード"))
                            .foregroundColor(LOColor.inkSecondary)
                    }
                }
                .font(.caption.weight(.semibold))
                Text(page.credit)
                    .font(.caption)
                    .foregroundColor(LOColor.inkSecondary)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .paperCard()
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .task {
            guard thumbnail == nil, let url = page.url else { return }
            thumbnail = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceThumbnailMaxPixelSize: 252,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}
