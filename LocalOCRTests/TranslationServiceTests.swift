import XCTest
@testable import LocalOCR

/// Translation is on-device only; these check the parts that do not need the model.
final class TranslationServiceTests: XCTestCase {
    func testPromptsPerLevelAndLanguage() {
        for level in TranslationService.TranslationLevel.allCases {
            let ja = level.systemPrompt(for: .japanese)
            let en = level.systemPrompt(for: .english)
            XCTAssertFalse(ja.isEmpty)
            XCTAssertFalse(en.isEmpty)
            XCTAssertNotEqual(ja, en)
        }
        XCTAssertTrue(TranslationService.TranslationLevel.general.systemPrompt(for: .japanese).contains("【現代語訳】"))
        XCTAssertTrue(TranslationService.TranslationLevel.researcher.systemPrompt(for: .japanese).contains("【直訳】"))
        XCTAssertTrue(TranslationService.TranslationLevel.student.systemPrompt(for: .english).contains("[Vocabulary]"))
    }

    /// Same stored values as KotenOCR, so the settings keep their meaning.
    func testRawValues() {
        XCTAssertEqual(TranslationService.TranslationLevel.allCases.map(\.rawValue), ["general", "student", "researcher"])
        XCTAssertEqual(TranslationService.TargetLanguage.allCases.map(\.rawValue), ["ja", "en"])
    }

    func testSettingsDefaultsAndStoredValues() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TranslationServiceTests"))
        defaults.removePersistentDomain(forName: "TranslationServiceTests")
        XCTAssertEqual(TranslationService.loadLevel(defaults), .general)
        XCTAssertEqual(TranslationService.loadTargetLanguage(defaults), .japanese)
        defaults.set("researcher", forKey: TranslationService.levelKey)
        defaults.set("en", forKey: TranslationService.targetLanguageKey)
        XCTAssertEqual(TranslationService.loadLevel(defaults), .researcher)
        XCTAssertEqual(TranslationService.loadTargetLanguage(defaults), .english)
        defaults.set("bogus", forKey: TranslationService.levelKey)
        XCTAssertEqual(TranslationService.loadLevel(defaults), .general)
        defaults.removePersistentDomain(forName: "TranslationServiceTests")
    }

    func testTooLongTextIsRefusedBeforeTheModel() async {
        let text = String(repeating: "あ", count: TranslationService.maxTextLength + 1)
        do {
            _ = try await TranslationService.shared.translate(text: text)
            XCTFail("expected an error")
        } catch let error as TranslationService.TranslationError {
            guard case .textTooLong = error else { return XCTFail("got \(error)") }
        } catch {
            XCTFail("got \(error)")
        }
    }

    func testErrorAndStatusMessagesAreNotEmpty() {
        XCTAssertFalse(TranslationService.TranslationError.textTooLong.errorDescription?.isEmpty ?? true)
        XCTAssertFalse(TranslationService.TranslationError.localAIUnavailable.errorDescription?.isEmpty ?? true)
        for status in [TranslationService.LocalAIStatus.available, .intelligenceNotEnabled, .modelNotReady,
                       .deviceNotEligible, .osNotSupported] {
            XCTAssertFalse(status.message.isEmpty)
        }
        _ = TranslationService.localAIStatus  // must not crash on any OS
    }

    /// The onboarding replays a stored result; its boxes must fit the shipped image.
    func testOnboardingSampleLoads() throws {
        let sample = try XCTUnwrap(OnboardingSample.load(bundle: Bundle(for: ModelStore.self)))
        XCTAssertFalse(sample.rotated)
        XCTAssertGreaterThanOrEqual(sample.lines.count, 3)
        for line in sample.lines {
            XCTAssertEqual(line.box.count, 4)
            XCTAssertTrue(line.box.allSatisfy { (0...1).contains($0) })
            XCTAssertLessThan(line.box[0], line.box[2])
            XCTAssertLessThan(line.box[1], line.box[3])
        }
        XCTAssertNotNil(UIImage(named: "OnboardingSample", in: Bundle(for: ModelStore.self), with: nil))
    }
}
