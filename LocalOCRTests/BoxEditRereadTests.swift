import XCTest
import UIKit
@testable import LocalOCR

/// Re-reading hand-corrected boxes with each engine, on the bundled sample pages
/// (KotenOCR's BoxEditRereadTests, for the four engines of Local OCR).
/// The NDL and PP-OCR models are downloaded if they are not on the device yet.
@MainActor
final class BoxEditRereadTests: XCTestCase {
    private func image(_ name: String) throws -> CGImage {
        let bundle = Bundle(for: BoxEditRereadTests.self)
        guard let path = bundle.path(forResource: name, ofType: "jpg"),
              let ui = UIImage(contentsOfFile: path), let cg = ui.normalizedCGImage else {
            throw XCTSkip("sample not found: \(name).jpg")
        }
        return cg
    }

    private func ensureInstalled(_ kind: EngineKind) async throws {
        let store = ModelStore()
        if store.isInstalled(kind) { return }
        store.download(kind)
        let deadline = Date().addingTimeInterval(900)
        while Date() < deadline {
            switch store.status[kind] {
            case .installed: return
            case .failed(let m): throw XCTSkip("download failed: \(m)")
            default: try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw XCTSkip("download timed out")
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    /// Deletes the longest line, draws a box over the same place (a little off), reads it again
    /// and checks that the text comes back and that ordering keeps every line.
    private func deleteThenRedraw(_ kind: EngineKind, page: String) async throws {
        let cg = try image(page)
        let recognizer = Recognizer()
        let result = try await recognizer.run(kind, on: cg)
        let target = try XCTUnwrap(result.lines.max { $0.text.count < $1.text.count })
        XCTAssertGreaterThanOrEqual(target.text.count, 3)
        let targetIndex = try XCTUnwrap(result.lines.firstIndex { $0.box == target.box })

        var editor = BoxEditor(detections: result.lines,
                               imageSize: CGSize(width: result.image.width, height: result.image.height))
        editor.delete(targetIndex)
        XCTAssertNotNil(editor.add(target.rect.insetBy(dx: -3, dy: -2)))
        XCTAssertEqual(editor.pendingCount, 1)

        let recognized = try await recognizer.reread(kind, boxes: editor.pending.map(\.detection), in: result.image)
        XCTAssertEqual(recognized.count, 1)
        let text = recognized[0].text
        print("[reread] \(kind.rawValue): \"\(text)\" vs \"\(target.text)\"")
        XCTAssertLessThanOrEqual(levenshtein(text, target.text), max(2, target.text.count / 3),
                                 "re-read \"\(text)\" vs original \"\(target.text)\"")

        let ordered = recognizer.orderReading(kind, editor.detections(applying: recognized),
                                              imageWidth: result.image.width, imageHeight: result.image.height)
        XCTAssertEqual(ordered.count, result.lines.count)
        editor.commitRecognition(ordered)
        XCTAssertEqual(editor.pendingCount, 0)
        XCTAssertTrue(editor.detections.contains { $0.text == text })
    }

    func testVisionRedraw() async throws {
        try await deleteThenRedraw(.vision, page: "sample_modern")
    }

    func testKotenRedraw() async throws {
        try await ensureInstalled(.ndlKoten)
        try await deleteThenRedraw(.ndlKoten, page: "koten_page")
    }

    func testModernRedraw() async throws {
        try await ensureInstalled(.ndlModern)
        try await deleteThenRedraw(.ndlModern, page: "sample_modern")
    }

    func testPPOCRRedraw() async throws {
        try await ensureInstalled(.ppocr)
        try await deleteThenRedraw(.ppocr, page: "sample_modern")
    }
}

/// Order used after box edits for Vision and PP-OCR.
final class ReadingOrderFallbackTests: XCTestCase {
    private func line(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ t: String) -> Detection {
        Detection(box: [x, y, x + w, y + h], score: 1, classId: 0, className: "line_main", text: t)
    }

    func testHorizontalRowsTopToBottomThenLeftToRight() {
        let lines = [line(300, 12, 200, 30, "B"), line(10, 100, 400, 30, "C"), line(10, 10, 250, 30, "A")]
        let ordered = ReadingOrderFallback.order(lines, imageWidth: 600, imageHeight: 200)
        XCTAssertEqual(ordered.map(\.text), ["A", "B", "C"])
    }

    func testTallBoxesCountAsVerticalPage() {
        let lines = [line(400, 10, 30, 300, "1"), line(350, 10, 30, 300, "2"), line(10, 10, 300, 30, "x")]
        XCTAssertTrue(ReadingOrderFallback.isVerticalPage(lines))
        XCTAssertFalse(ReadingOrderFallback.isVerticalPage([line(10, 10, 300, 30, "x")]))
    }
}
