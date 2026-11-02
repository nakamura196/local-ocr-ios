import SwiftUI

/// Settings for the modern-language translation (from KotenOCR). On-device AI only, so there is
/// no provider, API key, endpoint or model to choose.
struct TranslationSettingsView: View {
    @AppStorage(TranslationService.targetLanguageKey) private var targetRaw = TranslationService.TargetLanguage.japanese.rawValue
    @AppStorage(TranslationService.levelKey) private var levelRaw = TranslationService.TranslationLevel.general.rawValue
    @State private var status: TranslationService.LocalAIStatus = .osNotSupported

    private var level: TranslationService.TranslationLevel {
        TranslationService.TranslationLevel(rawValue: levelRaw) ?? .general
    }

    var body: some View {
        List {
            Group {
                Section(header: Text(String(localized: "settings_translation_options", defaultValue: "翻訳オプション"))) {
                    Picker(String(localized: "settings_target_language", defaultValue: "翻訳先言語"), selection: $targetRaw) {
                        ForEach(TranslationService.TargetLanguage.allCases, id: \.rawValue) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .accessibilityIdentifier("settings_target_language")

                    Picker(String(localized: "settings_translation_level", defaultValue: "解説レベル"), selection: $levelRaw) {
                        ForEach(TranslationService.TranslationLevel.allCases, id: \.rawValue) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .accessibilityIdentifier("settings_translation_level")

                    Text(level.description)
                        .font(.caption)
                        .foregroundColor(LOColor.inkSecondary)
                }

                Section(header: Text(String(localized: "settings_translation_engine", defaultValue: "翻訳に使う AI")),
                        footer: Text(String(localized: "settings_translation_footer", defaultValue: "Apple の端末内の AI で訳します。読み取った文字は端末の外に送りません。AI の訳と解説には誤りが含まれることがあります。"))) {
                    Label(status.message,
                          systemImage: status == .available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundColor(status == .available ? LOColor.ok : LOColor.danger)
                        .accessibilityIdentifier("local_ai_status")
                }
            }
            .listRowBackground(LOColor.washiCard)
        }
        .scrollContentBackground(.hidden)
        .washiBackground()
        .navigationTitle(String(localized: "settings_translation_nav", defaultValue: "現代語訳"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { status = TranslationService.localAIStatus }
    }
}
