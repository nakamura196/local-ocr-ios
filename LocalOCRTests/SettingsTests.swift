import XCTest
@testable import LocalOCR

final class SettingsTests: XCTestCase {
    func testFeedbackURL() throws {
        let url = try XCTUnwrap(SettingsView.feedbackURL(appVersion: "0.1.0 (3)", device: "iPhone", systemVersion: "18.0"))
        XCTAssertEqual(url.scheme, "mailto")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, SettingsView.feedbackAddress)
        let subject = comps.queryItems?.first { $0.name == "subject" }?.value
        XCTAssertEqual(subject, "Local OCR (iOS) Feedback (v0.1.0 (3))")
    }
}
