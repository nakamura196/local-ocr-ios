import Foundation
import CoreGraphics
import Vision

/// Apple's on-device text recognition (no download). Returns one Detection per recognised line,
/// in Vision's own reading order.
enum VisionEngine {
    static let languages = ["ja-JP", "en-US", "zh-Hans", "zh-Hant"]

    static func process(image: CGImage) async throws -> [Detection] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = false
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = languages.filter { supported.contains($0) }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let w = CGFloat(image.width), h = CGFloat(image.height)
            var out: [Detection] = []
            for (i, obs) in (request.results ?? []).enumerated() {
                guard let top = obs.topCandidates(1).first else { continue }
                // Vision boxes are normalised with the origin at the bottom left.
                let r = obs.boundingBox
                let box = [Int(r.minX * w), Int((1 - r.maxY) * h), Int(r.maxX * w), Int((1 - r.minY) * h)]
                out.append(Detection(box: box, score: top.confidence, classId: 0, className: "line_main",
                                     text: top.string, id: i))
            }
            return out
        }.value
    }
}
