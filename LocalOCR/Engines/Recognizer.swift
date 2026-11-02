import Foundation
import CoreGraphics

/// One page read by one engine.
struct PageResult {
    let engine: EngineKind
    let image: CGImage
    let lines: [Detection]
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
