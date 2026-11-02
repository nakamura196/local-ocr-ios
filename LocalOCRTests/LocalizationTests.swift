import XCTest
@testable import LocalOCR

/// ja と en の文言がそろっているか、書式の指定子が食い違っていないかを確かめる。
final class LocalizationTests: XCTestCase {
    private func table(_ lang: String, _ name: String = "Localizable") throws -> [String: String] {
        let app = Bundle(for: ModelStore.self)
        let url = try XCTUnwrap(app.url(forResource: name, withExtension: "strings", subdirectory: nil, localization: lang),
                                "\(lang).lproj/\(name).strings がアプリに入っていない")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    private func specifiers(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"%(\d+\$)?(\.\d+)?(lld|ld|d|@|f)"#)
        let found = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }
        // 位置指定（%1$@）と位置なし（%@）は同じ物として、順に並べて比べる
        return found.map { $0.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }.sorted()
    }

    func testSameKeys() throws {
        for name in ["Localizable", "InfoPlist"] {
            let ja = try table("ja", name), en = try table("en", name)
            XCTAssertEqual(Set(ja.keys), Set(en.keys), name)
        }
    }

    func testSameFormatSpecifiers() throws {
        let ja = try table("ja"), en = try table("en")
        for (key, jaValue) in ja {
            XCTAssertEqual(specifiers(jaValue), specifiers(en[key] ?? ""), key)
        }
    }

    func testEnglishInterpolation() throws {
        let en = try table("en")
        let format = try XCTUnwrap(en["download_size_mismatch"])
        XCTAssertEqual(String(format: format, "rec.onnx", Int64(10), Int64(20)),
                       "The size of rec.onnx does not match (10 / 20 bytes). Please try again.")
    }
}
