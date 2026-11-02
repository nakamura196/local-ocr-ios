import XCTest
@testable import LocalOCR

final class SettingsTests: XCTestCase {
    /// Product IDs must start with the app's bundle id, or App Store Connect refuses them.
    @MainActor
    func testTipProductIDsUseBundleID() throws {
        let bundleID = try XCTUnwrap(Bundle(for: ModelStore.self).bundleIdentifier)
        XCTAssertEqual(TipJarManager.productIDs.count, 3)
        for id in TipJarManager.productIDs {
            XCTAssertTrue(id.hasPrefix(bundleID + ".tip."), id)
        }
        XCTAssertEqual(Set(TipJarManager.productIDs.map(TipJarManager.emoji(for:))).count, 3)
    }

    func testFeedbackURL() throws {
        let url = try XCTUnwrap(SettingsView.feedbackURL(appVersion: "0.1.0 (3)", device: "iPhone", systemVersion: "18.0"))
        XCTAssertEqual(url.scheme, "mailto")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, SettingsView.feedbackAddress)
        let subject = comps.queryItems?.first { $0.name == "subject" }?.value
        XCTAssertEqual(subject, "Local OCR (iOS) Feedback (v0.1.0 (3))")
    }
}
