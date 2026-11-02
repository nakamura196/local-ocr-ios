import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Holds the three screens (home → page → result) and the pickers they share.
struct ContentView: View {
    @EnvironmentObject var store: ModelStore
    @EnvironmentObject var recognizer: Recognizer
    @AppStorage("engine") private var engineRaw = EngineKind.vision.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var showModels = false
    @State private var showSamples = false
    @State private var showHistory = false
    @State private var showSettings = false
    @AppStorage(SettingsKey.saveToLibrary) private var saveToLibrary = false
    /// The history record of the page on screen, so later edits can go back to it.
    @State private var historyItemID: UUID?
    /// The result was opened from History: "back" returns to the list instead of the page.
    @State private var cameFromHistory = false
    @State private var image: CGImage?
    @State private var result: PageResult?
    @State private var errorMessage: String?

    private var engine: EngineKind { EngineKind(rawValue: engineRaw) ?? .vision }

    var body: some View {
        ZStack {
            if let result {
                ResultView(result: result,
                           backTitle: cameFromHistory ? String(localized: "history_title", defaultValue: "履歴") : nil,
                           onBack: {
                               if cameFromHistory {
                                   withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) { reset() }
                                   showHistory = true
                               } else {
                                   withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) { self.result = nil }
                               }
                           },
                           onNew: { withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) { reset() } })
                    .transition(LOMotion.rise(reduceMotion: reduceMotion))
            } else if let image {
                PageView(image: image, engineRaw: $engineRaw,
                         onBack: { withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) { reset() } },
                         onModels: { showModels = true },
                         onRead: { Task { await read() } })
                    .transition(LOMotion.rise(reduceMotion: reduceMotion))
            } else {
                HomeView(engineRaw: $engineRaw, photoItem: $photoItem,
                         onCamera: { showCamera = true },
                         onFiles: { showFiles = true },
                         onModels: { showModels = true },
                         onSample: { showSamples = true },
                         onHistory: { showHistory = true },
                         onSettings: { showSettings = true },
                         onOpenHistoryItem: { item in loadHistoryItem(item) })
                    .transition(.opacity)
            }
        }
        .washiBackground()
        .sheet(isPresented: $showModels) {
            NavigationStack {
                ModelsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "done", defaultValue: "完了")) { showModels = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showSamples) {
            SampleSheet(onSelect: { page in loadSample(page) })
        }
        .sheet(isPresented: $showHistory) {
            HistoryListView(onSelect: { item in loadHistoryItem(item) },
                            onStartCamera: { showCamera = true })
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { picked in
                guard let picked else { return }
                if saveToLibrary { UIImageWriteToSavedPhotosAlbum(picked, nil, nil, nil) }
                setImage(picked)
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { res in
            guard case .success(let url) = res else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) { setImage(ui) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    setImage(ui)
                }
                photoItem = nil
            }
        }
        .alert(String(localized: "error_title", defaultValue: "読み取れませんでした"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "ok", defaultValue: "OK")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            fallBackToInstalled()
            #if DEBUG
            loadDemoImage()
            loadDemoSheet()
            #endif
        }
        .onChange(of: store.status) { _, _ in fallBackToInstalled() }
    }

    #if DEBUG
    /// Screenshots: `-demoImage <path>` opens that file, `-demoRead YES` also reads it.
    private func loadDemoImage() {
        let defaults = UserDefaults.standard
        guard image == nil, let path = defaults.string(forKey: "demoImage"),
              let ui = UIImage(contentsOfFile: path) else { return }
        setImage(ui)
        if defaults.bool(forKey: "demoRead") { Task { await read() } }
    }

    private func loadDemoSheet() {
        if UserDefaults.standard.bool(forKey: "demoModels") { showModels = true }
        if UserDefaults.standard.bool(forKey: "demoSamples") { showSamples = true }
        if UserDefaults.standard.bool(forKey: "demoHistory") { showHistory = true }
        if UserDefaults.standard.bool(forKey: "demoSettings") { showSettings = true }
    }
    #endif

    private func fallBackToInstalled() {
        if store.status[engine] != .installed { engineRaw = EngineKind.vision.rawValue }
    }

    private func reset() {
        image = nil
        result = nil
        historyItemID = nil
        cameFromHistory = false
    }

    private func setImage(_ ui: UIImage) {
        withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) {
            image = ui.normalizedCGImage()
            result = nil
            historyItemID = nil
            cameFromHistory = false
        }
    }

    /// Shows a saved page as it was read: the stored image (already straightened) and its lines.
    private func loadHistoryItem(_ item: HistoryItem) {
        guard let ui = UIImage(contentsOfFile: HistoryManager.shared.imageURL(for: item).path),
              let cg = ui.normalizedCGImage() else { return }
        withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) {
            image = cg
            result = PageResult(engine: item.engineKind ?? .vision, image: cg,
                                lines: item.detections, seconds: item.seconds ?? 0)
            historyItemID = item.id
            cameFromHistory = true
        }
    }

    /// Opens a bundled sample page. If its engine is downloaded, reads it straight away;
    /// otherwise leaves the page open and shows the models screen.
    private func loadSample(_ page: SamplePage) {
        guard let ui = page.loadImage() else { return }
        setImage(ui)
        if store.status[page.engine] == .installed {
            engineRaw = page.engine.rawValue
            Task { await read() }
        } else {
            showModels = true
        }
    }

    private func read() async {
        guard let image else { return }
        LOHaptics.impact(.medium)
        do {
            let r = try await recognizer.run(engine, on: image)
            LOHaptics.notify(.success)
            // Every reading is kept, also a second reading of the same page with another engine.
            let id = HistoryManager.shared.save(image: r.image, detections: r.lines, text: r.text,
                                                engine: r.engine, seconds: r.seconds)
            withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) {
                result = r
                historyItemID = id
                cameFromHistory = false
            }
        } catch {
            LOHaptics.notify(.error)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: ModelStore
    @Binding var engineRaw: String
    @Binding var photoItem: PhotosPickerItem?
    let onCamera: () -> Void
    let onFiles: () -> Void
    let onModels: () -> Void
    let onSample: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void
    let onOpenHistoryItem: (HistoryItem) -> Void

    @ObservedObject private var historyManager = HistoryManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = 0

    private var recentItems: [HistoryItem] { Array(historyManager.items.prefix(3)) }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .opacity(appeared >= 1 ? 1 : 0)

                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 28)
                        if recentItems.isEmpty {
                            intro
                        } else {
                            recentSection
                        }
                        Spacer(minLength: 28)
                        engines
                            .padding(.bottom, 22)
                        mainCard
                        secondaryRow
                            .padding(.top, 12)
                        sampleLink
                            .padding(.top, 8)
                        privacyNote
                            .padding(.top, 16)
                    }
                    .opacity(appeared >= 2 ? 1 : 0)
                    .offset(y: appeared >= 2 || reduceMotion ? 0 : 10)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
                .frame(minHeight: geo.size.height)
            }
        }
        .onAppear(perform: playEntrance)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                LOSeal(size: 40)
                Text("Local OCR")
                    .font(.mincho(28, relativeTo: .title, bold: true))
                    .foregroundColor(LOColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: onHistory) {
                IconLabel(systemName: "clock")
            }
            .buttonStyle(.loGlassCircle)
            .accessibilityLabel(Text(String(localized: "history_button", defaultValue: "履歴")))
            .accessibilityIdentifier("home_history_button")
            Button(action: onModels) {
                IconLabel(systemName: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.loGlassCircle)
            .accessibilityLabel(Text(String(localized: "models_title", defaultValue: "読み取りモデル")))
            .accessibilityIdentifier("home_models_button")
            Button(action: onSettings) {
                IconLabel(systemName: "gearshape")
            }
            .buttonStyle(.loGlassCircle)
            .accessibilityLabel(Text(String(localized: "settings_title", defaultValue: "設定")))
            .accessibilityIdentifier("home_settings_button")
        }
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Text(String(localized: "brand_tagline", defaultValue: "画像の文字を、この端末の中で読む"))
                .font(.mincho(20, relativeTo: .title3, bold: true))
                .tracking(1)
                .foregroundColor(LOColor.ink)
                .multilineTextAlignment(.center)
            LOColor.ai.opacity(0.6)
                .frame(width: 32, height: 1.5)
                .accessibilityHidden(true)
            Text(String(localized: "brand_sub",
                        defaultValue: "くずし字から現代の活字、外国語まで。\n資料に合う方式を選べます。"))
                .font(.mincho(15, relativeTo: .subheadline))
                .foregroundColor(LOColor.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
    }

    // MARK: Recent pages

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "home_recent", defaultValue: "最近の読み取り"))
                    .font(.mincho(16, relativeTo: .headline, bold: true))
                    .foregroundColor(LOColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onHistory) {
                    Text(String(localized: "home_all_history", defaultValue: "すべて見る"))
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(LOColor.ai)
                }
            }
            .padding(.horizontal, 24)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                    Button { onOpenHistoryItem(item) } label: {
                        RecentThumbnail(item: item, height: recentThumbnailHeight)
                    }
                    .buttonStyle(PaperCardButtonStyle())
                    .accessibilityLabel(Text(HistoryListView.accessibilityLabel(for: item)))
                    .accessibilityIdentifier("home_recent_\(index)")
                }
            }
            // With one or two pages the tiles grow and sit in the middle, so the page does not look empty.
            .frame(maxWidth: recentItems.count == 1 ? 200 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, recentItems.count == 2 ? 36 : 20)
        }
    }

    /// Smaller than KotenOCR's: the engine cards also have to fit on the home screen.
    private var recentThumbnailHeight: CGFloat {
        switch recentItems.count {
        case 1: return 200
        case 2: return 150
        default: return 112
        }
    }

    private var engines: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "engine_picker", defaultValue: "読み取りの方式"))
                    .font(.mincho(16, relativeTo: .headline, bold: true))
                    .foregroundColor(LOColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onModels) {
                    Text(String(localized: "home_manage_models", defaultValue: "モデルを管理"))
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(LOColor.ai)
                }
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(EngineKind.allCases) { kind in
                        EngineCard(kind: kind,
                                   status: store.status[kind] ?? .notInstalled,
                                   selected: engineRaw == kind.rawValue) {
                            if store.status[kind] == .installed {
                                LOHaptics.impact(.light)
                                withAnimation(LOMotion.spring(0.3, reduceMotion: reduceMotion)) { engineRaw = kind.rawValue }
                            } else {
                                onModels()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }

    private var mainCard: some View {
        Button(action: {
            LOHaptics.impact(.medium)
            onCamera()
        }) {
            HStack(spacing: 20) {
                Image(systemName: "camera")
                    .font(.system(size: 40, weight: .light))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "home_take_photo", defaultValue: "撮影して読む"))
                        .font(.mincho(28, relativeTo: .title, bold: true))
                    Text(String(localized: "home_take_photo_sub", defaultValue: "資料をカメラで写す"))
                        .font(.subheadline)
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(LOColor.washi)
            .padding(26)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(RoundedRectangle(cornerRadius: 18).fill(LOColor.ink))
            .shadow(color: LOColor.ink.opacity(0.25), radius: 12, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PaperCardButtonStyle())
        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
        .accessibilityIdentifier("home_camera_button")
        .padding(.horizontal, 20)
    }

    private var secondaryRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            PhotosPicker(selection: $photoItem, matching: .images) {
                secondaryLabel(icon: "photo", title: String(localized: "input_photos", defaultValue: "写真から選ぶ"))
            }
            .buttonStyle(PaperCardButtonStyle())
            .accessibilityIdentifier("home_photo_button")

            Button(action: onFiles) {
                secondaryLabel(icon: "folder", title: String(localized: "input_files", defaultValue: "ファイルから選ぶ"))
            }
            .buttonStyle(PaperCardButtonStyle())
            .accessibilityIdentifier("home_files_button")
        }
        .padding(.horizontal, 20)
    }

    private func secondaryLabel(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .accessibilityHidden(true)
            Text(title)
                .font(.mincho(17, relativeTo: .headline, bold: true))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(LOColor.ink)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 92)
        .paperCard()
    }

    /// A quiet text link: try the app on a bundled page without a book at hand.
    private var sampleLink: some View {
        Button(action: onSample) {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                    .accessibilityHidden(true)
                Text(String(localized: "home_try_sample", defaultValue: "サンプルの頁で試す"))
                    .underline(color: LOColor.ai.opacity(0.5))
            }
            .font(.mincho(15, relativeTo: .subheadline))
            .foregroundColor(LOColor.ink)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_sample_button")
        .padding(.horizontal, 20)
    }

    private var privacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .accessibilityHidden(true)
            Text(String(localized: "home_privacy", defaultValue: "画像も結果も、端末の外に送りません"))
        }
        .font(.footnote)
        .foregroundColor(LOColor.inkSecondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private func playEntrance() {
        guard appeared == 0 else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { appeared = 2 }
            return
        }
        withAnimation(.easeInOut(duration: 0.45)) { appeared = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.55)) { appeared = 2 }
        }
    }
}

/// One engine on the home screen: selectable when installed, otherwise shows its download size.
private struct EngineCard: View {
    let kind: EngineKind
    let status: ModelStore.Status
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(selected ? LOColor.ai : LOColor.ink)
                    Spacer(minLength: 4)
                    badge
                }
                Text(kind.title)
                    .font(.mincho(15, relativeTo: .headline, bold: true))
                    .foregroundColor(LOColor.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(kind.tag)
                    .font(.caption)
                    .foregroundColor(LOColor.inkSecondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: 132, height: 128, alignment: .topLeading)
            .paperCard(cornerRadius: 14,
                       stroke: selected ? LOColor.ai : LOColor.rule,
                       lineWidth: selected ? 2.5 : 1)
            .opacity(isInstalled ? 1 : 0.72)
        }
        .buttonStyle(PaperCardButtonStyle())
        .accessibilityLabel(Text(String(localized: "engine_a11y_label", defaultValue: "\(kind.title)、\(kind.tag)")))
        .accessibilityValue(Text(accessibilityState))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("engine_card_\(kind.rawValue)")
    }

    private var isInstalled: Bool { status == .installed }

    @ViewBuilder private var badge: some View {
        switch status {
        case .installed:
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(LOColor.ai)
            }
        case .downloading(let p):
            ProgressView(value: p).progressViewStyle(.circular).controlSize(.small)
        case .notInstalled, .failed:
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle")
                Text(ByteCountFormatter.string(fromByteCount: kind.downloadSize, countStyle: .file))
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(LOColor.ai)
        }
    }

    private var accessibilityState: String {
        switch status {
        case .installed: return selected ? String(localized: "a11y_selected", defaultValue: "選択中") : ""
        case .downloading: return String(localized: "a11y_downloading", defaultValue: "ダウンロード中")
        case .notInstalled, .failed: return String(localized: "a11y_not_installed", defaultValue: "未ダウンロード。押すとモデルの画面を開きます")
        }
    }
}

// MARK: - Page (before reading)

struct PageView: View {
    @EnvironmentObject var store: ModelStore
    @EnvironmentObject var recognizer: Recognizer
    let image: CGImage
    @Binding var engineRaw: String
    let onBack: () -> Void
    let onModels: () -> Void
    let onRead: () -> Void

    private var engine: EngineKind { EngineKind(rawValue: engineRaw) ?? .vision }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    BackLabel(title: String(localized: "back", defaultValue: "戻る"))
                }
                .buttonStyle(.loGlass)
                .disabled(recognizer.isRunning)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .overlay { if recognizer.isRunning { ScanSweep() } }
                .paperMount()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            VStack(spacing: 12) {
                if recognizer.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().tint(LOColor.ai)
                        Text(String(localized: "reading_on_device", defaultValue: "この端末の中で読み取っています…"))
                            .font(.mincho(15, relativeTo: .subheadline))
                            .foregroundColor(LOColor.inkSecondary)
                    }
                    .transition(.opacity)
                } else {
                    engineMenu
                        .transition(.opacity)
                }

                Button(action: onRead) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.viewfinder")
                        Text(String(localized: "read", defaultValue: "読み取る"))
                            .font(.mincho(19, relativeTo: .headline, bold: true))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.loProminent)
                .disabled(recognizer.isRunning)
                .accessibilityIdentifier("read_button")
            }
            .animation(.easeInOut(duration: 0.2), value: recognizer.isRunning)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var engineMenu: some View {
        Menu {
            Picker(String(localized: "engine_picker", defaultValue: "読み取りの方式"), selection: $engineRaw) {
                ForEach(store.installedEngines) { kind in
                    Label(String(localized: "engine_picker_item", defaultValue: "\(kind.title)　\(kind.tag)"), systemImage: kind.symbol).tag(kind.rawValue)
                }
            }
            Divider()
            Button(action: onModels) {
                Label(String(localized: "home_manage_models", defaultValue: "モデルを管理"), systemImage: "square.and.arrow.down.on.square")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: engine.symbol)
                    .foregroundColor(LOColor.ai)
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.title)
                        .font(.mincho(16, relativeTo: .headline, bold: true))
                    Text(engine.tag)
                        .font(.caption)
                        .foregroundColor(LOColor.inkSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(LOColor.inkSecondary)
            }
            .foregroundColor(LOColor.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .paperCard(cornerRadius: 14, lineWidth: 1)
        }
        .accessibilityIdentifier("engine_menu")
    }
}

/// A band of 藍 light that sweeps down the page while it is being read.
private struct ScanSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                LOColor.washi.opacity(0.18)
                LinearGradient(colors: [LOColor.ai.opacity(0), LOColor.ai.opacity(0.35), LOColor.ai.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: max(40, geo.size.height * 0.16))
                    .offset(y: down ? geo.size.height : -geo.size.height * 0.16)
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { down = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Helpers

extension UIImage {
    /// The pixels upright (camera photos carry their rotation as a flag), as a CGImage.
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return drawn.cgImage
    }
}

/// The system camera.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onPick(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onPick(nil)
            parent.dismiss()
        }
    }
}
