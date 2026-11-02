import SwiftUI
import AVFoundation

/// Settings (from KotenOCR): about, models, camera, appearance, language, tips, feedback, licenses, links.
/// Left out until the matching features move over: translation, onboarding and tips replay, the tilt guide
/// and auto-deskew (they belong to KotenOCR's own camera).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    @AppStorage(SettingsKey.saveToLibrary) private var saveToLibrary = false
    @State private var showRestartAlert = false
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    static let feedbackAddress = "nakamura.satoru@mail.u-tokyo.ac.jp"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .system }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    aboutSection
                    modelsSection
                    cameraSection
                    themeSection
                    languageSection
                    feedbackSection
                    licenseSection
                    linkSection
                }
                .listRowBackground(LOColor.washiCard)
            }
            .scrollContentBackground(.hidden)
            .washiBackground()
            .navigationTitle(String(localized: "settings_title", defaultValue: "設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done", defaultValue: "完了")) { dismiss() }
                        .accessibilityIdentifier("settings_done")
                }
            }
            .alert(String(localized: "language_restart_title", defaultValue: "再起動が必要"), isPresented: $showRestartAlert) {
                Button(String(localized: "ok", defaultValue: "OK")) {}
            } message: {
                Text(String(localized: "language_restart_message", defaultValue: "言語の変更を適用するにはアプリを再起動してください。"))
            }
        }
        .tint(LOColor.ai)
        .preferredColorScheme(appTheme.colorScheme)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(header: Text(String(localized: "settings_about", defaultValue: "このアプリについて"))) {
            HStack(spacing: 12) {
                Image("AppIconDisplay")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local OCR")
                        .font(.mincho(17, relativeTo: .headline, bold: true))
                        .foregroundColor(LOColor.ink)
                    Text(String(localized: "settings_version", defaultValue: "バージョン") + " \(appVersion)")
                        .font(.caption)
                        .foregroundColor(LOColor.inkSecondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            Text(String(localized: "settings_about_privacy",
                        defaultValue: "画像も読み取った文字も、端末の外に送りません。インターネットを使うのは、読み取りモデルをダウンロードするときだけです。"))
                .font(.footnote)
                .foregroundColor(LOColor.inkSecondary)
        }
    }

    // MARK: - Models

    private var modelsSection: some View {
        Section(header: Text(String(localized: "models_title", defaultValue: "読み取りモデル"))) {
            NavigationLink {
                ModelsView()
            } label: {
                Label {
                    Text(String(localized: "settings_manage_models", defaultValue: "モデルのダウンロードと削除"))
                } icon: {
                    Image(systemName: "square.and.arrow.down.on.square").foregroundColor(LOColor.ai)
                }
            }
            .accessibilityIdentifier("settings_models")
        }
    }

    // MARK: - Camera

    private var cameraSection: some View {
        Section(header: Text(String(localized: "settings_camera", defaultValue: "カメラ"))) {
            HStack {
                Text(String(localized: "settings_camera_permission", defaultValue: "カメラの許可"))
                Spacer()
                switch cameraStatus {
                case .authorized:
                    Text(String(localized: "camera_status_authorized", defaultValue: "許可済み"))
                        .foregroundColor(LOColor.ok)
                case .denied, .restricted:
                    Button(action: openSettings) {
                        Text(String(localized: "camera_status_denied", defaultValue: "許可されていません"))
                            .foregroundColor(LOColor.danger)
                    }
                case .notDetermined:
                    Text(String(localized: "camera_status_not_set", defaultValue: "未設定"))
                        .foregroundColor(LOColor.inkSecondary)
                @unknown default:
                    EmptyView()
                }
            }
            .onAppear { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }

            if cameraStatus == .denied || cameraStatus == .restricted {
                Button(action: openSettings) {
                    Label(String(localized: "camera_open_settings", defaultValue: "設定を開く"), systemImage: "gear")
                }
            }

            Toggle(String(localized: "settings_save_to_library", defaultValue: "撮った写真を写真ライブラリに保存"),
                   isOn: $saveToLibrary)
                .accessibilityIdentifier("settings_save_to_library")
        }
    }

    // MARK: - Appearance

    private var themeSection: some View {
        Section(header: Text(String(localized: "settings_theme", defaultValue: "外観"))) {
            Picker(String(localized: "settings_theme", defaultValue: "外観"), selection: $appThemeRaw) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings_theme")
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section(header: Text(String(localized: "settings_language", defaultValue: "言語"))) {
            Picker(String(localized: "settings_language", defaultValue: "言語"), selection: $appLanguage) {
                Text(String(localized: "language_system", defaultValue: "システム")).tag("system")
                Text(String(localized: "language_ja", defaultValue: "日本語")).tag("ja")
                Text(String(localized: "language_en", defaultValue: "English")).tag("en")
            }
            .onChange(of: appLanguage) { _, newValue in
                Self.applyLanguage(newValue)
                showRestartAlert = true
            }
        }
    }

    static func applyLanguage(_ language: String) {
        if language == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        Section(header: Text(String(localized: "settings_feedback", defaultValue: "フィードバック"))) {
            Button(action: sendFeedback) {
                Label(String(localized: "settings_send_feedback", defaultValue: "フィードバックを送る"), systemImage: "envelope")
            }
        }
    }

    private func sendFeedback() {
        if let url = Self.feedbackURL(appVersion: appVersion,
                                      device: UIDevice.current.model,
                                      systemVersion: UIDevice.current.systemVersion) {
            UIApplication.shared.open(url)
        }
    }

    static func feedbackURL(appVersion: String, device: String, systemVersion: String) -> URL? {
        let subject = "Local OCR (iOS) Feedback (v\(appVersion))"
        let body = """


        ---
        Device: \(device)
        iOS: \(systemVersion)
        App: \(appVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackAddress
        components.queryItems = [URLQueryItem(name: "subject", value: subject),
                                 URLQueryItem(name: "body", value: body)]
        return components.url
    }

    // MARK: - Licenses

    private var licenseSection: some View {
        Section(header: Text(String(localized: "settings_licenses", defaultValue: "ライセンス"))) {
            licenseLink(name: "NDL古典籍OCR-Lite", summary: "CC-BY-4.0 — 国立国会図書館",
                        holder: "© 国立国会図書館 (National Diet Library)",
                        license: "Creative Commons Attribution 4.0 International (CC-BY-4.0)",
                        repo: "https://github.com/ndl-lab/ndlkotenocr-lite", text: LicenseText.ccby4)
            licenseLink(name: "NDLOCR-Lite", summary: "CC-BY-4.0 — 国立国会図書館",
                        holder: "© 国立国会図書館 (National Diet Library)",
                        license: "Creative Commons Attribution 4.0 International (CC-BY-4.0)",
                        repo: "https://github.com/ndl-lab/ndlocr-lite", text: LicenseText.ccby4)
            licenseLink(name: "PP-OCRv6", summary: "Apache-2.0 — PaddlePaddle",
                        holder: "© PaddlePaddle Authors",
                        license: "Apache License, Version 2.0",
                        repo: "https://github.com/PaddlePaddle/PaddleOCR", text: LicenseText.apache2)
            licenseLink(name: "ONNX Runtime", summary: "MIT License — Microsoft",
                        holder: "© Microsoft Corporation",
                        license: "MIT License",
                        repo: "https://github.com/microsoft/onnxruntime", text: LicenseText.mit)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings_sample_pages_title", defaultValue: "サンプルの頁"))
                    .font(.body)
                Text(String(localized: "settings_sample_pages_credit", defaultValue: ""))
                    .font(.caption)
                    .foregroundColor(LOColor.inkSecondary)
            }
        }
    }

    private func licenseLink(name: String, summary: String, holder: String, license: String,
                             repo: String, text: String) -> some View {
        NavigationLink {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(name).font(.title2).bold()
                    Text(holder).font(.subheadline)
                    Text(license).font(.subheadline).foregroundColor(LOColor.inkSecondary)
                    if let url = URL(string: repo) {
                        Link(repo, destination: url).font(.subheadline)
                    }
                    Divider()
                    Text(text).font(.caption).foregroundColor(LOColor.inkSecondary)
                }
                .padding()
            }
            .washiBackground()
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(summary).font(.caption).foregroundColor(LOColor.inkSecondary)
            }
        }
    }

    // MARK: - Links

    private var linkSection: some View {
        Section(header: Text(String(localized: "settings_links", defaultValue: "リンク"))) {
            externalLink(String(localized: "settings_link_site", defaultValue: "Local OCR のサイト"), "https://lo.ldas.jp/")
            externalLink(String(localized: "settings_link_source", defaultValue: "ソースコード（GitHub）"),
                         "https://github.com/nakamura196/local-ocr-ios")
            externalLink("NDL Lab GitHub", "https://github.com/ndl-lab")
        }
    }

    @ViewBuilder
    private func externalLink(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(LOColor.inkSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

enum SettingsKey {
    static let saveToLibrary = "saveToLibrary"
}
