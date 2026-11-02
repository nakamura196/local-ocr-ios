import SwiftUI
import AVFoundation

/// First-run introduction (from KotenOCR): what the app does, camera permission, how to use it.
/// Shown once; Settings can show it again.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var introFinished = false

    static let defaultsKey = "hasCompletedOnboarding"
    private let lastPage = 2

    var body: some View {
        ZStack {
            WashiBackground()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    introPage.tag(0)
                    cameraPermissionPage.tag(1)
                    howToUsePage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(action: {
                    if currentPage < lastPage {
                        withAnimation { currentPage += 1 }
                    } else {
                        hasCompletedOnboarding = true
                    }
                }) {
                    Text(currentPage < lastPage
                         ? String(localized: "onboarding_next", defaultValue: "次へ")
                         : String(localized: "onboarding_start", defaultValue: "はじめる"))
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.loProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(currentPage > 0 || introFinished ? 1 : 0)
                .accessibilityIdentifier(currentPage < lastPage ? "onboarding_next_button" : "onboarding_start_button")
            }
        }
        .tint(LOColor.ai)
    }

    // MARK: - Page 1: Intro (animated, about 3 s)

    private var introPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingIntroAnimation(finished: $introFinished)
                    .padding(.top, 12)
                VStack(spacing: 14) {
                    Text(String(localized: "onboarding_heading", defaultValue: "文字を、\nその場で読む"))
                        .font(.mincho(30, relativeTo: .largeTitle, bold: true))
                        .foregroundColor(LOColor.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(localized: "onboarding_intro", defaultValue: "端末の中だけで文字を読み取るアプリ。\n古典籍のくずし字から近代の活字、英文まで、方式を選んで読めます。画像も文字も端末の外に送りません。"))
                        .font(.body)
                        .foregroundColor(LOColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 48)
                .opacity(introFinished ? 1 : 0)
                .offset(y: introFinished ? 0 : 12)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Page 2: Camera permission

    private var cameraPermissionPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: cameraStatus == .authorized ? "checkmark.circle.fill" : "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(LOColor.ai)
                .accessibilityHidden(true)
            Text(String(localized: "onboarding_camera_title", defaultValue: "カメラへのアクセス"))
                .font(.mincho(26, relativeTo: .title2, bold: true))
                .foregroundColor(LOColor.ink)
            Text(String(localized: "onboarding_camera_description", defaultValue: "本や書類の頁を撮って読み取るために、\nカメラへのアクセスを許可してください。"))
                .font(.body)
                .foregroundColor(LOColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            switch cameraStatus {
            case .authorized:
                Text(String(localized: "onboarding_camera_granted", defaultValue: "カメラは許可済みです"))
                    .font(.subheadline)
                    .foregroundColor(LOColor.ai)
            case .denied, .restricted:
                VStack(spacing: 12) {
                    Text(String(localized: "onboarding_camera_denied", defaultValue: "カメラが許可されていません"))
                        .font(.subheadline)
                        .foregroundColor(LOColor.danger)
                    Button(action: openSettings) {
                        Text(String(localized: "camera_open_settings", defaultValue: "設定を開く"))
                            .font(.headline)
                            .padding(.horizontal, 32)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(.loGlass)
                }
            default:
                Button(action: requestCameraPermission) {
                    Text(String(localized: "onboarding_allow_camera", defaultValue: "カメラを許可する"))
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.loGlass)
                .accessibilityIdentifier("onboarding_allow_camera")
            }
            Spacer()
            Spacer()
        }
        .onAppear { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }
    }

    // MARK: - Page 3: How to use

    private var howToUsePage: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text(String(localized: "onboarding_howto_title", defaultValue: "使い方"))
                    .font(.mincho(26, relativeTo: .title2, bold: true))
                    .foregroundColor(LOColor.ink)
                    .padding(.top, 48)
                VStack(alignment: .leading, spacing: 20) {
                    howToStep(icon: "camera.viewfinder",
                              title: String(localized: "onboarding_step1_title", defaultValue: "撮影する"),
                              description: String(localized: "onboarding_step1_desc", defaultValue: "頁をカメラで撮影（「写真」やファイルの画像も選べます）"))
                    howToStep(icon: "text.viewfinder",
                              title: String(localized: "onboarding_step2_title", defaultValue: "方式を選んで読む"),
                              description: String(localized: "onboarding_step2_desc", defaultValue: "Apple Vision はすぐに使えます。古典籍・近代の活字などの方式は、はじめにモデルをダウンロードします"))
                    howToStep(icon: "doc.on.doc",
                              title: String(localized: "onboarding_step3_title", defaultValue: "コピーする"),
                              description: String(localized: "onboarding_step3_desc", defaultValue: "読み取った文字をコピー。TXT・PDF でも書き出せます"))
                    howToStep(icon: "sparkles",
                              title: String(localized: "onboarding_step4_title", defaultValue: "現代語訳"),
                              description: String(localized: "onboarding_step4_desc", defaultValue: "対応する機種では、端末内の AI で現代語訳と解説を付けられます"))
                }
                .padding(.horizontal, 36)
            }
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private func howToStep(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(LOColor.ai)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.mincho(18, relativeTo: .headline, bold: true))
                    .foregroundColor(LOColor.ink)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(LOColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// First-run animation. Replays a real recognition result of the sample page
/// (Resources/onboarding_sample_ocr.json, the 古典籍 engine's output, taken over from KotenOCR):
/// the grey page, the 藍 beam, then the boxes in reading order (right to left), then the first
/// lines. About 3 s; no OCR runs here. With Reduce Motion the final state is shown still.
private struct OnboardingIntroAnimation: View {
    @Binding var finished: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var sweep: CGFloat = 0
    @State private var revealed = 0
    @State private var showLines = false

    private let sample = OnboardingSample.load()
    private let image = UIImage(named: "OnboardingSample")
    private var boxes: [CGRect] {
        (sample?.lines ?? []).map { l in
            CGRect(x: l.box[0], y: l.box[1], width: l.box[2] - l.box[0], height: l.box[3] - l.box[1])
        }
    }
    private var scanned: Bool { revealed > 0 }

    var body: some View {
        VStack(spacing: 14) {
            if let image {
                ZStack {
                    // Not yet read: grey and slightly sepia.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .grayscale(1)
                        .colorMultiply(Color(red: 0.95, green: 0.9, blue: 0.82))
                        .brightness(-0.05)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .mask(alignment: .trailing) {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: geo.size.width * (scanned ? 1 : sweep))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .overlay {
                            GeometryReader { geo in
                                ZStack(alignment: .topLeading) {
                                    if !scanned && sweep > 0 && sweep < 1 {
                                        OnboardingBeam(height: geo.size.height)
                                            .position(x: geo.size.width * (1 - sweep), y: geo.size.height / 2)
                                    }
                                    OnboardingBoxes(boxes: boxes, revealed: revealed, size: geo.size)
                                }
                            }
                        }
                }
                .paperMount()
                .frame(maxHeight: 330)
                // Required by the library's reuse terms (cropped and overlaid = modified).
                Text(String(localized: "sample_genji_credit", defaultValue: "『源氏物語』（東京大学総合図書館所蔵）を改変"))
                    .font(.caption2)
                    .foregroundColor(LOColor.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            if showLines, let lines = sample?.lines.prefix(3) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(LOColor.box(index))
                            Text(line.text)
                                .font(.mincho(16, relativeTo: .body))
                                .foregroundColor(LOColor.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard(cornerRadius: 14, lineWidth: 1)
                .transition(.opacity)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 16)
        .padding(.horizontal, 32)
        .accessibilityHidden(true)
        .onAppear(perform: play)
    }

    private func play() {
        guard !appeared else { return }
        let count = boxes.count
        if reduceMotion || count == 0 {
            appeared = true
            sweep = 1
            revealed = count
            showLines = count > 0
            finished = true
            return
        }
        // 0–500 ms: the page appears, grey.
        withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        // 500–1300 ms: the 藍 beam sweeps right → left.
        after(0.5) { withAnimation(.linear(duration: 0.8)) { sweep = 1 } }
        // 1300–2100 ms: the boxes appear one by one in reading order.
        let step = min(0.08, 0.8 / Double(count))
        for i in 1...count {
            after(1.3 + step * Double(i)) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { revealed = i }
            }
        }
        // 2100–2600 ms: the first lines, then heading and "Next".
        after(2.15) { withAnimation(.easeOut(duration: 0.35)) { showLines = true } }
        after(2.5) { withAnimation(.easeOut(duration: 0.45)) { finished = true } }
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }
}

/// Line boxes appearing one by one, in the result screen's colours. Boxes are normalized (0...1).
private struct OnboardingBoxes: View {
    let boxes: [CGRect]
    let revealed: Int
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(boxes.prefix(revealed).enumerated()), id: \.offset) { index, b in
                let rect = CGRect(x: b.minX * size.width, y: b.minY * size.height,
                                  width: b.width * size.width, height: b.height * size.height)
                let isNewest = index == revealed - 1
                let color = LOColor.box(index)
                Rectangle()
                    .fill(color.opacity(isNewest ? 0.25 : 0.1))
                    .overlay(Rectangle().stroke(color, lineWidth: isNewest ? 2.5 : 1.5))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.25).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The 藍 scanning beam with a faint tail on the already-read (right) side.
private struct OnboardingBeam: View {
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(LOColor.ai)
                .frame(width: 3)
                .shadow(color: LOColor.ai, radius: 6)
                .shadow(color: LOColor.ai.opacity(0.6), radius: 18)
            LinearGradient(colors: [LOColor.ai.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 70)
        }
        .frame(height: height + 20)
        .offset(x: 35)
        .allowsHitTesting(false)
    }
}

/// A real recognition result for the onboarding sample page, replayed on first launch so the app
/// does not need any model before the reader has started. Taken over from KotenOCR (its
/// OnboardingSampleGenerator made the JSON with the 古典籍 engine); do not edit the JSON by hand.
struct OnboardingSample: Codable {
    struct Line: Codable {
        /// x1, y1, x2, y2, normalized to the image size (0...1).
        let box: [Double]
        let text: String
    }

    let source: String
    /// True if auto-deskew rotated the page; then the boxes would not match the shipped image.
    let rotated: Bool
    /// In reading order.
    let lines: [Line]

    static func load(bundle: Bundle = .main) -> OnboardingSample? {
        guard let url = bundle.url(forResource: "onboarding_sample_ocr", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OnboardingSample.self, from: data)
    }
}
