import Foundation
import CoreGraphics

/// One page read by one engine.
struct PageResult {
    let engine: EngineKind
    let image: CGImage
    var lines: [Detection]
    let seconds: Double

    var text: String { lines.filter { !$0.text.isEmpty }.map(\.text).joined(separator: "\n") }
}

/// Runs whichever engine the reader picked. Models are loaded on first use and kept in memory.
@MainActor
final class Recognizer: ObservableObject {
    @Published private(set) var isRunning = false

    private let ndl = OCREngine()
    private var ppocr: PPOCREngine?

    func run(_ kind: EngineKind, on image: CGImage) async throws -> PageResult {
        isRunning = true
        defer { isRunning = false }
        let start = Date()
        let result: (CGImage, [Detection])
        switch kind {
        case .vision:
            result = (image, try await VisionEngine.process(image: image))
        case .ndlKoten:
            let r = try await ndl.run(mode: .koten, image: image)
            result = (r.image ?? image, r.detections.filter { !$0.text.isEmpty })
        case .ndlModern:
            let r = try await ndl.run(mode: .ndl, image: image)
            result = (r.image ?? image, r.detections.filter { $0.isTextLine })
        case .ppocr:
            let engine = try loadPPOCR()
            result = (image, try await InferenceThread.shared.run { try engine.process(image: image) })
        }
        return PageResult(engine: kind, image: result.0, lines: result.1, seconds: Date().timeIntervalSince(start))
    }

    /// Reads hand-corrected boxes again with `kind`. Returns the boxes with `text` filled in, in the same order.
    func reread(_ kind: EngineKind, boxes: [Detection], in image: CGImage) async throws -> [Detection] {
        guard !boxes.isEmpty else { return [] }
        isRunning = true
        defer { isRunning = false }
        switch kind {
        case .vision:
            return try await VisionEngine.recognize(boxes: boxes, in: image)
        case .ndlKoten:
            _ = try ndl.sharedEnv()
            return try await ndl.recognize(boxes: boxes, in: image, mode: .koten)
        case .ndlModern:
            _ = try ndl.sharedEnv()
            return try await ndl.recognize(boxes: boxes, in: image, mode: .ndl)
        case .ppocr:
            let engine = try loadPPOCR()
            return try await InferenceThread.shared.run { try engine.recognize(boxes: boxes, in: image) }
        }
    }

    /// Puts lines back in reading order after an edit. The NDL engines use their own order
    /// (block xy-cut). Vision and PP-OCR give no order of their own for new boxes: a page of mostly
    /// tall boxes (vertical writing) uses the same xy-cut, otherwise lines go top to bottom, left to right.
    func orderReading(_ kind: EngineKind, _ lines: [Detection], imageWidth: Int, imageHeight: Int) -> [Detection] {
        switch kind {
        case .ndlKoten, .ndlModern:
            return ndl.orderReading(lines, imageWidth: imageWidth, imageHeight: imageHeight)
        case .vision, .ppocr:
            return ReadingOrderFallback.order(lines, imageWidth: imageWidth, imageHeight: imageHeight)
        }
    }

    /// Forget a loaded engine whose files were deleted.
    func unload(_ kind: EngineKind) {
        switch kind {
        case .vision: break
        case .ndlKoten: ndl.unload(mode: .koten)
        case .ndlModern: ndl.unload(mode: .ndl)
        case .ppocr: ppocr = nil
        }
    }

    func handleMemoryWarning() {
        ndl.handleMemoryWarning()
    }

    private func loadPPOCR() throws -> PPOCREngine {
        if let ppocr { return ppocr }
        guard let det = ModelFiles.path("ppocrv6-det", "onnx"),
              let detCfg = ModelFiles.path("ppocrv6-det", "yml"),
              let rec = ModelFiles.path("ppocrv6-rec", "onnx"),
              let recCfg = ModelFiles.path("ppocrv6-rec", "yml") else {
            throw NSError(domain: "PPOCR", code: 2, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "ppocr_not_downloaded", defaultValue: "PP-OCRv6 のモデルがまだダウンロードされていません。")])
        }
        let engine = try PPOCREngine(env: ndl.sharedEnv(), detModelPath: det, detConfigPath: detCfg,
                                     recModelPath: rec, recConfigPath: recCfg)
        ppocr = engine
        return engine
    }
}

/// Reading order for engines without one of their own (Vision, PP-OCR), used after box edits.
enum ReadingOrderFallback {
    static func isVerticalPage(_ lines: [Detection]) -> Bool {
        let boxes = lines.filter { $0.box.count >= 4 }
        guard !boxes.isEmpty else { return false }
        let tall = boxes.filter { ($0.box[3] - $0.box[1]) > ($0.box[2] - $0.box[0]) * 3 / 2 }.count
        return tall * 2 > boxes.count
    }

    static func order(_ lines: [Detection], imageWidth: Int, imageHeight: Int) -> [Detection] {
        if isVerticalPage(lines) {
            return ReadingOrderProcessor().process(detections: lines, imageWidth: imageWidth, imageHeight: imageHeight)
        }
        return horizontal(lines)
    }

    /// Top to bottom; lines sharing more than half the height of the shorter one are one row, left to right.
    static func horizontal(_ lines: [Detection]) -> [Detection] {
        let byTop = lines.filter { $0.box.count >= 4 }.sorted { $0.box[1] < $1.box[1] }
        var rows: [[Detection]] = []
        for line in byTop {
            if var row = rows.last, let anchor = row.first {
                let overlap = min(anchor.box[3], line.box[3]) - max(anchor.box[1], line.box[1])
                let shorter = min(anchor.box[3] - anchor.box[1], line.box[3] - line.box[1])
                if overlap * 2 > shorter {
                    row.append(line)
                    rows[rows.count - 1] = row
                    continue
                }
            }
            rows.append([line])
        }
        return rows.flatMap { $0.sorted { $0.box[0] < $1.box[0] } } + lines.filter { $0.box.count < 4 }
    }
}
