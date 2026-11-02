import Foundation
import CoreGraphics
import os
import OnnxRuntimeBindings

/// PP-OCRv6 (detection + recognition). Port of the desktop Local OCR `ppocr` package
/// (PaddleOCR, Apache-2.0). Files: PPOCRConfig (inference.yml), PPOCRPixels, PPOCRDetect (DB post-processing).
final class PPOCREngine: @unchecked Sendable {
    private let detSession: ORTSession
    private let recSession: ORTSession
    private let detInput: String
    private let recInput: String
    private let chars: [String]
    private let params: PPOCRParams
    /// Long side of the image given to the detector. The desktop app uses 2048 px.
    var detLongSide = 2048
    private let recMaxWidth = 3200

    init(env: ORTEnv, detModelPath: String, detConfigPath: String,
         recModelPath: String, recConfigPath: String) throws {
        func read(_ p: String) throws -> String {
            guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { throw PPOCRConfigError.unreadable(p) }
            return s
        }
        let detYml = try read(detConfigPath)
        let recYml = try read(recConfigPath)
        params = PPOCRConfig.params(detYml: detYml, recYml: recYml)
        chars = try PPOCRConfig.characterDict(recYml)
        detSession = try ORTSession(env: env, modelPath: detModelPath, sessionOptions: try ORTSessionOptions())
        recSession = try ORTSession(env: env, modelPath: recModelPath, sessionOptions: try ORTSessionOptions())
        guard let d = try detSession.inputNames().first, let r = try recSession.inputNames().first else {
            throw NSError(domain: "PPOCR", code: 3, userInfo: [NSLocalizedDescriptionKey: "model has no input"])
        }
        detInput = d
        recInput = r
    }

    /// One Detection per text line: box = [x1, y1, x2, y2] in pixels of `image`, `text`, `score`
    /// (recognition confidence 0...1), className "line_main", in reading order.
    func process(image: CGImage) throws -> [Detection] {
        try autoreleasepool { try processUnpooled(image: image) }
    }

    private func processUnpooled(image: CGImage) throws -> [Detection] {
        guard let rgb = PPOCRImage(cgImage: image) else { return [] }
        var result: [Detection] = []
        for box in try detect(rgb) {
            guard let crop = cropLine(rgb, quad: box.quad) else { continue }
            let (text, textScore) = try readCrop(crop)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let xs = box.quad.map { $0.x }, ys = box.quad.map { $0.y }
            let x1 = xs.min()!, y1 = ys.min()!
            let x2 = max(xs.max()!, x1 + 1), y2 = max(ys.max()!, y1 + 1)
            result.append(Detection(box: [x1, y1, x2, y2], score: Float(textScore), classId: 0,
                                    className: "line_main", text: text, id: result.count))
        }
        return result
    }

    // MARK: detection

    /// Detector memory grows with its input area: measured on an iPhone 16e (Debug), the peak was
    /// 1.25 GB at 960 px, 2.07 GB at 1280 px and 3.14 GB at 1600 px on a 2048 x 1446 page, about
    /// 1.6 GB per megapixel. The app is killed when it passes its limit (3.3 GB there, less on 4 GB
    /// iPhones), so the input is shrunk to fit in part of the memory still available.
    static let detBytesPerPixel = 1_750.0
    static let detMinLongSide = 736

    static func detScale(width W: Int, height H: Int, longSide: Int, availableBytes: Double) -> Double {
        var scale = min(1.0, Double(longSide) / Double(max(W, H)))
        // 0 means "not reported" (simulator, Mac): no limit.
        guard availableBytes > 0 else { return scale }
        let budget = availableBytes * 0.6
        let pixels = Double(W) * Double(H) * scale * scale
        if pixels * detBytesPerPixel > budget {
            scale *= (budget / detBytesPerPixel / pixels).squareRoot()
        }
        let floor = min(1.0, Double(detMinLongSide) / Double(max(W, H)))
        return max(scale, floor)
    }

    private func detect(_ img: PPOCRImage) throws -> [PPOCRBox] {
        let W = img.width, H = img.height
        let scale = Self.detScale(width: W, height: H, longSide: detLongSide,
                                  availableBytes: Double(os_proc_available_memory()))
        var small = img
        if scale != 1.0 {
            let nw = max(Int((Double(W) * scale).rounded(.toNearestOrEven)), 1)
            let nh = max(Int((Double(H) * scale).rounded(.toNearestOrEven)), 1)
            small = PPOCRPixels.resizeBicubicPIL(img, width: nw, height: nh)
        }
        let (dw, dh) = PPOCRDetect.detSize(small.width, small.height)
        let resized = PPOCRPixels.resizeLinearCV(small, width: dw, height: dh)
        let tensor = PPOCRPixels.detTensor(resized)
        let out = try run(detSession, input: detInput, tensor: tensor, shape: [1, 3, dh, dw])
        guard out.data.count >= dh * dw else {
            throw NSError(domain: "PPOCR", code: 4, userInfo: [NSLocalizedDescriptionKey: "unexpected detector output"])
        }
        return PPOCRDetect.findBoxes(prob: Array(out.data.prefix(dh * dw)), dh: dh, dw: dw, outW: W, outH: H, params: params)
    }

    private func run(_ session: ORTSession, input: String, tensor: [Float], shape: [Int]) throws -> (data: [Float], shape: [Int]) {
        let data = NSMutableData(bytes: tensor, length: tensor.count * MemoryLayout<Float>.stride)
        let value = try ORTValue(tensorData: data, elementType: .float, shape: shape.map { NSNumber(value: $0) })
        let names = try session.outputNames()
        guard let first = names.first else { return ([], []) }
        let results = try session.run(withInputs: [input: value], outputNames: Set([first]),
                                      runOptions: ORTMemory.runOptions())
        guard let output = results[first] else { return ([], []) }
        let bytes = try output.tensorData() as Data
        let dims = try output.tensorTypeAndShapeInfo().shape.map { $0.intValue }
        return (bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }, dims)
    }

    // MARK: crop

    private func cropLine(_ img: PPOCRImage, quad: [(x: Int, y: Int)]) -> PPOCRImage? {
        let c = PPOCRDetect.rectCorners(PPOCRDetect.minAreaRect(quad.map { (Double($0.x), Double($0.y)) }))
        let p0 = c[0], p1 = c[1], p2 = c[2], p3 = c[3]
        func dist(_ a: PPOCRPoint, _ b: PPOCRPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
        let w = Int(max(dist(p0, p1), dist(p2, p3)))
        let h = Int(max(dist(p0, p3), dist(p1, p2)))
        if w <= 0 || h <= 0 { return nil }
        let out = PPOCRPixels.warpQuad(img, p0: p0, p1: p1, p3: p3, width: w, height: h)
        return Double(h) / Double(w) >= 1.5 ? out.rotatedLeft() : out
    }

    // MARK: recognition

    private func readCrop(_ crop: PPOCRImage) throws -> (String, Double) {
        let recH = params.recHeight
        let ratio = Double(crop.width) / Double(crop.height)
        var width = Int(Double(recH) * max(Double(params.recMinWidth) / Double(recH), ratio))
        let rw: Int
        if width > recMaxWidth {
            width = recMaxWidth; rw = recMaxWidth
        } else {
            rw = min(Int((Double(recH) * ratio).rounded(.up)), width)
        }
        let small = PPOCRPixels.resizeLinearCV(crop, width: rw, height: recH)
        let t = PPOCRPixels.bgrTensor(small, mean: [127.5, 127.5, 127.5], std: [127.5, 127.5, 127.5])
        var tensor = t
        if rw != width {
            tensor = [Float](repeating: 0, count: 3 * recH * width)
            for c in 0..<3 {
                for y in 0..<recH {
                    for x in 0..<rw { tensor[(c * recH + y) * width + x] = t[(c * recH + y) * rw + x] }
                }
            }
        }
        let out = try run(recSession, input: recInput, tensor: tensor, shape: [1, 3, recH, width])
        return decodeCTC(out)
    }

    /// Greedy CTC over a [T, C] map (C = chars.count + 2: blank, the list, a trailing space).
    private func decodeCTC(_ res: (data: [Float], shape: [Int])) -> (String, Double) {
        let out = res.data
        guard let classes = res.shape.last, classes > 0, out.count >= classes else { return ("", 0) }
        let steps = out.count / classes
        var text = ""
        var prev = -1
        var sum = 0.0, n = 0
        for t in 0..<steps {
            var best = 0
            var top = -Float.infinity
            let base = t * classes
            for c in 0..<classes where out[base + c] > top { top = out[base + c]; best = c }
            if best != 0 && best != prev {
                text += best - 1 < chars.count ? chars[best - 1] : " "
                sum += Double(top); n += 1
            }
            prev = best
        }
        return (text, n > 0 ? sum / Double(n) : 0)
    }
}
