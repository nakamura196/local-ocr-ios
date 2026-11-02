import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Modern-language translation of the recognised text, from KotenOCR.
/// Only the on-device model (Apple Foundation Models, iOS 26+) is used: the text never leaves the
/// device, like the pages themselves. KotenOCR's external APIs (OpenRouter, OpenAI, custom) are
/// left out on purpose.
actor TranslationService {
    static let shared = TranslationService()

    static let levelKey = "translation_level"
    static let targetLanguageKey = "translation_target_language"
    static let maxTextLength = 5000

    enum TargetLanguage: String, CaseIterable {
        case japanese = "ja"
        case english = "en"

        var displayName: String {
            switch self {
            case .japanese: return String(localized: "target_lang_ja", defaultValue: "日本語（現代語）")
            case .english: return String(localized: "target_lang_en", defaultValue: "English")
            }
        }
    }

    enum TranslationLevel: String, CaseIterable {
        case general
        case student
        case researcher

        var displayName: String {
            switch self {
            case .general: return String(localized: "level_general", defaultValue: "一般向け")
            case .student: return String(localized: "level_student", defaultValue: "学生向け")
            case .researcher: return String(localized: "level_researcher", defaultValue: "研究者向け")
            }
        }

        var description: String {
            switch self {
            case .general: return String(localized: "level_general_desc", defaultValue: "わかりやすい現代語訳と簡単な解説")
            case .student: return String(localized: "level_student_desc", defaultValue: "正確な訳と語注・文法解説")
            case .researcher: return String(localized: "level_researcher_desc", defaultValue: "原文に忠実な直訳と詳細な注釈")
            }
        }

        func systemPrompt(for language: TargetLanguage) -> String {
            switch language {
            case .japanese: return japanesePrompt
            case .english: return englishPrompt
            }
        }

        // Same prompts as KotenOCR.
        private var japanesePrompt: String {
            switch self {
            case .general:
                return """
                あなたは古典日本語の専門家です。与えられた古文を現代日本語に翻訳してください。
                以下の形式で出力してください：

                【現代語訳】
                自然で読みやすい現代語訳を書いてください。

                【解説】
                この文章がどのような作品・資料のものか（わかる場合）、時代背景や内容の簡単な説明を2〜3文で書いてください。
                """
            case .student:
                return """
                あなたは古典日本語の専門家です。与えられた古文を学習者向けに詳しく翻訳・解説してください。
                以下の形式で出力してください：

                【現代語訳】
                原文に忠実で正確な現代語訳を書いてください。

                【語注】
                重要な古語・文法事項を箇条書きで説明してください（例：「あけぼの」＝夜明け）。

                【解説】
                作品名（わかる場合）、時代、ジャンル、文学的特徴などを説明してください。
                """
            case .researcher:
                return """
                あなたは古典日本語・古典文学の研究者です。与えられた古文を学術的に正確に分析してください。
                以下の形式で出力してください：

                【直訳】
                原文の構造に忠実な逐語的翻訳を書いてください。

                【語釈】
                重要な語句について、語義・用法・文法的説明を箇条書きで記してください。

                【解題】
                作品・資料の同定（可能な場合）、成立時期、ジャンル、書誌的情報、文学史的・歴史的位置づけについて記してください。
                """
            }
        }

        private var englishPrompt: String {
            switch self {
            case .general:
                return """
                You are an expert in classical Japanese literature. Translate the given classical Japanese (kobun/kuzushiji) text into modern English.
                Use the following format:

                [Translation]
                Provide a natural, readable English translation.

                [Commentary]
                Briefly describe what kind of text/work this is (if identifiable), its historical period, and context in 2-3 sentences.
                """
            case .student:
                return """
                You are an expert in classical Japanese literature. Translate and annotate the given classical Japanese text for learners.
                Use the following format:

                [Translation]
                Provide an accurate English translation faithful to the original.

                [Vocabulary]
                List important classical Japanese terms with their readings and meanings (e.g., あけぼの (akebono) = dawn).

                [Commentary]
                Explain the work (if identifiable), its period, genre, and literary significance.
                """
            case .researcher:
                return """
                You are a scholar of classical Japanese language and literature. Provide an academic analysis of the given classical Japanese text.
                Use the following format:

                [Literal Translation]
                Provide a word-by-word translation preserving the original syntactic structure.

                [Glossary]
                For key terms, provide: reading, meaning, grammatical analysis, and usage notes.

                [Bibliographic Note]
                Identify the work (if possible), its date of composition, genre, bibliographic details, and place in literary/historical context.
                """
            }
        }
    }

    enum TranslationError: LocalizedError {
        case textTooLong
        case localAIUnavailable

        var errorDescription: String? {
            switch self {
            case .textTooLong:
                return String(localized: "translation_error_too_long", defaultValue: "テキストが長すぎます")
            case .localAIUnavailable:
                return String(localized: "translation_error_local_ai", defaultValue: "端末内の AI はこの機種では使えません。iOS 26 以降と Apple Intelligence に対応した機種が必要です。")
            }
        }
    }

    // MARK: - Settings (UserDefaults, nonisolated: plain reads and writes)

    nonisolated static func loadLevel(_ defaults: UserDefaults = .standard) -> TranslationLevel {
        defaults.string(forKey: levelKey).flatMap(TranslationLevel.init(rawValue:)) ?? .general
    }

    nonisolated static func loadTargetLanguage(_ defaults: UserDefaults = .standard) -> TargetLanguage {
        defaults.string(forKey: targetLanguageKey).flatMap(TargetLanguage.init(rawValue:)) ?? .japanese
    }

    // MARK: - On-device model availability

    enum LocalAIStatus: Equatable {
        case available
        case intelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
        case osNotSupported

        var message: String {
            switch self {
            case .available:
                return String(localized: "local_ai_ready", defaultValue: "端末内の AI が使えます")
            case .intelligenceNotEnabled:
                return String(localized: "local_ai_not_enabled", defaultValue: "Apple Intelligence が有効になっていません。「設定」>「Apple Intelligence と Siri」で有効にしてください。")
            case .modelNotReady:
                return String(localized: "local_ai_model_not_ready", defaultValue: "AI のモデルをダウンロード中です。Wi‑Fi につないで、しばらくお待ちください。")
            case .deviceNotEligible:
                return String(localized: "local_ai_device_not_eligible", defaultValue: "この機種は端末内の AI に対応していません。iPhone 15 Pro 以降が必要です。")
            case .osNotSupported:
                return String(localized: "local_ai_os_not_supported", defaultValue: "端末内の AI には iOS 26 以降が必要です。")
            }
        }
    }

    nonisolated static var localAIStatus: LocalAIStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .intelligenceNotEnabled
                case .modelNotReady: return .modelNotReady
                case .deviceNotEligible: return .deviceNotEligible
                @unknown default: return .deviceNotEligible
                }
            @unknown default:
                return .deviceNotEligible
            }
        }
        #endif
        return .osNotSupported
    }

    // MARK: - Translation

    func translate(text: String) async throws -> String {
        guard text.count <= Self.maxTextLength else { throw TranslationError.textTooLong }
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw TranslationError.localAIUnavailable
            }
            let prompt = Self.loadLevel().systemPrompt(for: Self.loadTargetLanguage())
            let session = LanguageModelSession(instructions: prompt)
            let response = try await session.respond(to: text)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw TranslationError.localAIUnavailable
    }
}
