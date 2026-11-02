import Foundation

/// One file the app fetches on demand. URLs are pinned to upstream commits so every install gets
/// the same bytes as the desktop Local OCR and KotenOCR; the size is checked after download.
struct ModelFile: Hashable {
    let url: URL
    /// Name under the app's model folder (also what `ModelFiles.path` looks up).
    let localName: String
    let size: Int64
}

/// The recognition engines the app offers. The order is the order on screen.
enum EngineKind: String, CaseIterable, Identifiable {
    case vision
    case ndlKoten
    case ndlModern
    case ppocr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vision: return String(localized: "engine_vision_title", defaultValue: "Apple Vision")
        case .ndlKoten: return String(localized: "engine_koten_title", defaultValue: "NDL古典籍OCR Lite")
        case .ndlModern: return String(localized: "engine_ndl_title", defaultValue: "NDLOCR Lite")
        case .ppocr: return String(localized: "engine_ppocr_title", defaultValue: "PP-OCRv6")
        }
    }

    var summary: String {
        switch self {
        case .vision:
            return String(localized: "engine_vision_summary",
                          defaultValue: "iPhone に入っている文字認識。現代の活字・手書き。日本語・英語・中国語。ダウンロード不要で速い。")
        case .ndlKoten:
            return String(localized: "engine_koten_summary",
                          defaultValue: "江戸期以前の版本・写本、くずし字。国立国会図書館のモデル。")
        case .ndlModern:
            return String(localized: "engine_ndl_summary",
                          defaultValue: "明治以降の日本語の活字。国立国会図書館のモデル。")
        case .ppocr:
            return String(localized: "engine_ppocr_summary",
                          defaultValue: "活字を行ごとに読む。中国語・英語・日本語、ラテン文字の言語。")
        }
    }

    var license: String {
        switch self {
        case .vision: return "Apple"
        case .ndlKoten, .ndlModern: return "CC BY 4.0 — National Diet Library, Japan"
        case .ppocr: return "Apache-2.0 — PaddlePaddle"
        }
    }

    var files: [ModelFile] {
        switch self {
        case .vision: return []
        case .ndlKoten: return ModelCatalog.koten
        case .ndlModern: return ModelCatalog.ndl
        case .ppocr: return ModelCatalog.ppocr
        }
    }

    var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var needsDownload: Bool { !files.isEmpty }
}

enum ModelCatalog {
    // rtmdet: the 2024-12-24 file (40,188,733 bytes), the one KotenOCR ships. The first commit (95692df)
    // has an older 40,189,181-byte file; parseq is the same in both.
    static let kotenCommit = "22be4cc98d542afc7422f9a67d0529850b1e4e12"
    static let ndlCommit = "109e62759d59002673765e0f7f2cfc663443585d"
    // Same pins as the desktop Local OCR (src/local_ocr/engines/ppocr.py).
    static let ppocrDetRev = "61323801669c338b7891481ec7bac61ce31b576a"
    static let ppocrRecRev = "50c7eacafc52fa7bcf4194e8cd08e46f8558504b"

    private static func github(_ repo: String, _ commit: String, _ name: String, _ size: Int64) -> ModelFile {
        ModelFile(url: URL(string: "https://raw.githubusercontent.com/ndl-lab/\(repo)/\(commit)/src/model/\(name)")!,
                  localName: name, size: size)
    }

    private static func hf(_ repo: String, _ rev: String, _ name: String, as local: String, _ size: Int64) -> ModelFile {
        ModelFile(url: URL(string: "https://huggingface.co/PaddlePaddle/\(repo)/resolve/\(rev)/\(name)")!,
                  localName: local, size: size)
    }

    static let koten: [ModelFile] = [
        github("ndlkotenocr-lite", kotenCommit, "rtmdet-s-1280x1280.onnx", 40_188_733),
        github("ndlkotenocr-lite", kotenCommit, "parseq-ndl-32x384-tiny-10.onnx", 37_752_180),
    ]

    static let ndl: [ModelFile] = [
        github("ndlocr-lite", ndlCommit, "deim-s-1024x1024.onnx", 40_256_763),
        github("ndlocr-lite", ndlCommit, "parseq-ndl-16x256-30-tiny-192epoch-tegaki3.onnx", 35_848_117),
        github("ndlocr-lite", ndlCommit, "parseq-ndl-16x384-50-tiny-146epoch-tegaki2.onnx", 36_920_058),
        github("ndlocr-lite", ndlCommit, "parseq-ndl-16x768-100-tiny-165epoch-tegaki2.onnx", 40_984_184),
    ]

    static let ppocr: [ModelFile] = [
        hf("PP-OCRv6_medium_det_onnx", ppocrDetRev, "inference.onnx", as: "ppocrv6-det.onnx", 62_032_837),
        hf("PP-OCRv6_medium_det_onnx", ppocrDetRev, "inference.yml", as: "ppocrv6-det.yml", 886),
        hf("PP-OCRv6_medium_rec_onnx", ppocrRecRev, "inference.onnx", as: "ppocrv6-rec.onnx", 76_554_979),
        hf("PP-OCRv6_medium_rec_onnx", ppocrRecRev, "inference.yml", as: "ppocrv6-rec.yml", 150_580),
    ]
}

/// Where model files live: downloaded files first, then the small configs bundled with the app.
enum ModelFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Models", isDirectory: true)
    }

    static func path(_ name: String, _ ext: String) -> String? {
        let downloaded = directory.appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: downloaded.path) { return downloaded.path }
        return Bundle.main.path(forResource: name, ofType: ext, inDirectory: "Models")
    }
}
