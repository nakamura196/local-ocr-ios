import XCTest
import UIKit
@testable import LocalOCR

/// Downloads the NDL models for real (about 230 MB) and reads sample pages.
/// Sample pages (from KotenOCR) are bundled with the tests, so this also runs on a device.
@MainActor
final class EndToEndTests: XCTestCase {
    private func image(_ name: String) throws -> CGImage {
        let bundle = Bundle(for: EndToEndTests.self)
        guard let path = bundle.path(forResource: name, ofType: "jpg"),
              let ui = UIImage(contentsOfFile: path), let cg = ui.normalizedCGImage() else {
            throw XCTSkip("sample not found: \(name).jpg")
        }
        return cg
    }

    private func install(_ kind: EngineKind, store: ModelStore) async throws {
        store.download(kind)
        let deadline = Date().addingTimeInterval(900)
        while Date() < deadline {
            switch store.status[kind] {
            case .installed: return
            case .failed(let m): XCTFail("download failed: \(m)"); return
            default: try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        XCTFail("download timed out")
    }

    func testKotenDownloadAndRead() async throws {
        let store = ModelStore()
        try await install(.ndlKoten, store: store)
        XCTAssertTrue(store.isInstalled(.ndlKoten))
        let r = try await Recognizer().run(.ndlKoten, on: try image("koten_page"))
        print("[e2e] koten lines=\(r.lines.count) sec=\(r.seconds)\n\(r.text.prefix(200))")
        XCTAssertGreaterThan(r.lines.count, 3)
    }

    func testModernDownloadAndRead() async throws {
        let store = ModelStore()
        try await install(.ndlModern, store: store)
        let r = try await Recognizer().run(.ndlModern, on: try image("sample_modern"))
        print("[e2e] ndl lines=\(r.lines.count) sec=\(r.seconds)\n\(r.text.prefix(200))")
        XCTAssertGreaterThan(r.lines.count, 3)
    }

    func testPPOCRDownloadAndRead() async throws {
        let store = ModelStore()
        try await install(.ppocr, store: store)
        let r = try await Recognizer().run(.ppocr, on: try image("sample_modern"))
        print("[e2e] ppocr lines=\(r.lines.count) sec=\(r.seconds)\n\(r.text.prefix(200))")
        XCTAssertGreaterThan(r.lines.count, 3)
    }

    func testVisionRead() async throws {
        let r = try await Recognizer().run(.vision, on: try image("sample_modern"))
        print("[e2e] vision lines=\(r.lines.count) sec=\(r.seconds)\n\(r.text.prefix(200))")
        XCTAssertGreaterThan(r.lines.count, 0)
    }

    func testDeleteRemovesFiles() async throws {
        let store = ModelStore()
        try await install(.ndlKoten, store: store)
        store.delete(.ndlKoten)
        XCTAssertFalse(store.isInstalled(.ndlKoten))
        XCTAssertEqual(store.status[.ndlKoten], .notInstalled)
    }
}
