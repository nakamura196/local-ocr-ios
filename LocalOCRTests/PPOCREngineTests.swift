import XCTest
import UIKit
import OnnxRuntimeBindings
@testable import LocalOCR

/// Runs the PP-OCRv6 port on a real printed page and compares it with the desktop Python result.
/// Models, page and Python reference are taken from the folder in PPOCR_REF_DIR (simulator only); skipped when unset.
final class PPOCREngineTests: XCTestCase {
    static let dir = ProcessInfo.processInfo.environment["PPOCR_REF_DIR"] ?? "/nonexistent"

    func testDetScaleFitsMemory() {
        let gb = 1_073_741_824.0
        // Unknown memory (simulator): only the 2048 px cap applies.
        XCTAssertEqual(PPOCREngine.detScale(width: 4096, height: 3000, longSide: 2048, availableBytes: 0), 0.5)
        // Plenty of memory: unchanged.
        XCTAssertEqual(PPOCREngine.detScale(width: 1000, height: 700, longSide: 2048, availableBytes: 3 * gb), 1.0)
        // iPhone 16e (3.3 GB free): a 2048 x 1446 page must shrink, peak estimate stays within 60%.
        let s = PPOCREngine.detScale(width: 2048, height: 1446, longSide: 2048, availableBytes: 3.3 * gb)
        XCTAssertLessThan(s, 1.0)
        XCTAssertLessThanOrEqual(2048 * 1446 * s * s * PPOCREngine.detBytesPerPixel, 3.3 * gb * 0.6 + 1)
        // Very little memory: never below 736 px on the long side.
        let tiny = PPOCREngine.detScale(width: 2048, height: 1446, longSide: 2048, availableBytes: 0.2 * gb)
        XCTAssertEqual(2048 * tiny, 736, accuracy: 0.5)
    }

    func testConfigParsing() throws {
        let yml = """
        PostProcess:
          character_dict:
          - a
          - 'b'
          - ''''
          - "\\u3000"
          - '!'
          - 　
          name: CTC
        """
        XCTAssertEqual(try PPOCRConfig.characterDict(yml), ["a", "b", "'", "\u{3000}", "!", "\u{3000}"])
    }

    private func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + [Int](repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    func testPrintedPageMatchesPython() throws {
        let m = "\(Self.dir)/ppocr"
        let paths = ["ppocrv6-det.onnx", "ppocrv6-det.yml", "ppocrv6-rec.onnx", "ppocrv6-rec.yml"].map { "\(m)/\($0)" }
        let imgPath = "\(Self.dir)/darwin41.jpg", refPath = "\(Self.dir)/darwin41.py.txt"
        for p in paths + [imgPath, refPath] where !FileManager.default.fileExists(atPath: p) {
            throw XCTSkip("missing \(p)")
        }
        guard let ui = UIImage(contentsOfFile: imgPath), let cg = ui.normalizedCGImage else { throw XCTSkip("bad image") }
        let env = try ORTEnv(loggingLevel: .warning)
        let engine = try PPOCREngine(env: env, detModelPath: paths[0], detConfigPath: paths[1],
                                     recModelPath: paths[2], recConfigPath: paths[3])
        let t0 = Date()
        let dets = try engine.process(image: cg)
        let sec = Date().timeIntervalSince(t0)
        let swiftLines = dets.map { $0.text }
        let ref = try String(contentsOfFile: refPath, encoding: .utf8)
        let refLines = ref.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        try swiftLines.joined(separator: "\n").write(toFile: "\(Self.dir)/darwin41.swift.txt", atomically: true, encoding: .utf8)

        let a = Array(swiftLines.joined(separator: "\n")), b = Array(refLines.joined(separator: "\n"))
        let dist = levenshtein(a, b)
        let agree = 1.0 - Double(dist) / Double(max(a.count, b.count, 1))
        var exact = 0
        for (s, r) in zip(swiftLines, refLines) where s == r { exact += 1 }
        print("[ppocr] swift lines=\(swiftLines.count) python lines=\(refLines.count) exactLines=\(exact) chars swift=\(a.count) py=\(b.count) editDistance=\(dist) agreement=\(agree) sec=\(sec)")
        for d in dets.prefix(3) { print("[ppocr] \(d.box) \(d.score) \(d.text)") }
        XCTAssertEqual(swiftLines.count, refLines.count, accuracy: 3)
        XCTAssertGreaterThan(agree, 0.97)
    }
}
