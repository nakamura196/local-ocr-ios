import XCTest
@testable import LocalOCR

final class ModelCatalogTests: XCTestCase {
    func testDownloadSizes() {
        XCTAssertEqual(EngineKind.vision.downloadSize, 0)
        XCTAssertEqual(EngineKind.ndlKoten.downloadSize, 77_940_913)
        XCTAssertEqual(EngineKind.ndlModern.downloadSize, 154_009_122)
    }

    func testLocalNamesAreUnique() {
        let names = EngineKind.allCases.flatMap(\.files).map(\.localName)
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testBundledConfigsFound() {
        XCTAssertNotNil(ModelFiles.path("NDLmoji", "yaml"))
        XCTAssertNotNil(ModelFiles.path("ndl-deim", "yaml"))
    }
}
