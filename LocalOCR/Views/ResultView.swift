import SwiftUI

/// The page with coloured line boxes on top, and the recognised lines below.
/// A line and its box share a colour; tapping either highlights both.
/// From KotenOCR's result screen: pinch and double-tap zoom, line numbers on the page, hiding the
/// boxes, the confidence slider, editing a line's text, and "Fix boxes" (move, resize, add, split,
/// merge, delete, then read the changed boxes again with the same engine).
struct ResultView: View {
    let result: PageResult
    /// The history record of this page; edits are written back to it.
    var historyItemID: UUID? = nil
    /// "履歴" when opened from History; nil shows "戻る" (back to the page to read it again).
    var backTitle: String? = nil
    /// True right after a reading (not from History): the 読 seal is pressed once.
    var playStamp: Bool = false
    let onBack: () -> Void
    let onNew: () -> Void

    @EnvironmentObject private var recognizer: Recognizer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The lines as the reader has corrected them (text edits and box edits).
    @State private var detections: [Detection]
    @StateObject private var edit = BoxEditModel()
    @State private var selected: Int?
    @State private var showBoxes = true
    @State private var copied = false
    /// A TXT or PDF written to the temporary folder, waiting to be handed to the share sheet.
    @State private var exportFile: ExportFile?
    /// Display filter only: lines scoring below this are hidden. Nothing stored changes.
    @State private var threshold: Float = ConfidenceFilter.defaultThreshold
    @State private var editingLine: EditingLine?
    @State private var editText = ""
    @State private var stampPhase = 0
    @State private var tab: ResultTab = .text
    @State private var translatedText: String?
    @State private var isTranslating = false
    @State private var translationError: String?

    // Zoom and pan of the page (same maths as KotenOCR).
    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @State private var stageSize: CGSize = .zero
    @State private var lastTouch: CGPoint = .zero
    @State private var isPinching = false

    init(result: PageResult, historyItemID: UUID? = nil, backTitle: String? = nil, playStamp: Bool = false,
         onBack: @escaping () -> Void, onNew: @escaping () -> Void) {
        self.result = result
        self.historyItemID = historyItemID
        self.backTitle = backTitle
        self.playStamp = playStamp
        self.onBack = onBack
        self.onNew = onNew
        _detections = State(initialValue: result.lines)
        _translatedText = State(initialValue: result.translation)
    }

    private var imageSize: CGSize { CGSize(width: result.image.width, height: result.image.height) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                stage
                    .frame(height: geo.size.height * (edit.isActive ? 0.6 : 0.42))
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                if edit.isActive {
                    BoxEditControls(model: edit, onCancel: cancelEditing, onDone: finishEditing, onReread: startReread)
                } else {
                    pageTools
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    summary
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                    confidenceControl
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                    tabPicker
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }

                ZStack {
                    if tab == .translation && !edit.isActive {
                        translationPanel.transition(.opacity)
                    } else {
                        lines.transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: tab)
            }
            .overlay(alignment: .bottom) { if !edit.isActive && !hidesBottomBar { bottomBar } }
        }
        .sheet(item: $editingLine) { line in editSheet(line.index) }
        .onAppear {
            playStampIfNeeded()
            #if DEBUG
            // Screenshots: `-demoTranslation YES` opens the translation tab.
            if UserDefaults.standard.bool(forKey: "demoTranslation") { tab = .translation }
            // Screenshots: `-demoBoxEdit YES` opens "Fix boxes" with the first line selected.
            if UserDefaults.standard.bool(forKey: "demoBoxEdit"), !detections.isEmpty {
                selected = 0
                beginEditing()
            }
            #endif
        }
        .onChange(of: edit.editor?.selected) { _, new in
            if edit.isActive, selected != new { selected = new }
        }
        .onChange(of: selected) { _, new in
            if edit.isActive, edit.editor?.selected != new { edit.editor?.selected = new }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                BackLabel(title: backTitle ?? String(localized: "back", defaultValue: "戻る"))
            }
            .buttonStyle(.loGlass)
            .disabled(edit.isActive)
            .accessibilityHint(backTitle == nil
                               ? Text(String(localized: "back_to_page_hint", defaultValue: "別の方式で読み直せます"))
                               : Text(""))
            Spacer()
            Menu {
                ShareLink(item: combinedText) {
                    Label(String(localized: "share_text", defaultValue: "テキストを共有"), systemImage: "text.bubble")
                }
                Button {
                    if let url = ExportManager.exportAsTXT(text: combinedText) { exportFile = ExportFile(url: url) }
                } label: {
                    Label(String(localized: "export_txt", defaultValue: "TXTで書き出す"), systemImage: "doc.text")
                }
                Button {
                    if let url = ExportManager.exportAsPDF(text: combinedText, image: result.image) { exportFile = ExportFile(url: url) }
                } label: {
                    Label(String(localized: "export_pdf", defaultValue: "PDFで書き出す"), systemImage: "doc.richtext")
                }
            } label: {
                IconLabel(systemName: "square.and.arrow.up")
                    .foregroundColor(LOColor.ink)
                    .loGlass(.regular, in: Circle(), interactive: true)
            }
            .disabled(detections.isEmpty || edit.isActive)
            .accessibilityLabel(Text(String(localized: "share", defaultValue: "共有")))
            .accessibilityIdentifier("share_menu")
        }
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Page (zoomable, with boxes)

    private var stage: some View {
        ZStack {
            LOColor.mount

            Image(decorative: result.image, scale: 1)
                .resizable()
                .scaledToFit()
                .overlay { boxesOverlay.allowsHitTesting(false) }
                .overlay {
                    if edit.isActive {
                        BoxEditCanvas(model: edit, imageSize: imageSize, zoom: zoom)
                    }
                }
                .overlay { tapOverlay.allowsHitTesting(!edit.isActive) }
                .scaleEffect(zoom)
                .offset(offset)

            // Touches for box editing live outside the zoomed image so they stay in screen space.
            if edit.isActive {
                BoxEditGestureLayer(model: edit, imageSize: imageSize,
                                    zoom: zoom, offset: $offset, steadyOffset: $steadyOffset,
                                    isPinching: isPinching,
                                    onHaptic: { LOHaptics.notify(.warning) },
                                    onDoubleTap: { toggleZoom(at: $0) })
            }
        }
        .clipped()
        .overlay(alignment: .topTrailing) { completionStamp }
        .padding(6)
        .background(LOColor.mount)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(LOColor.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: Color(red: 0.31, green: 0.24, blue: 0.12).opacity(0.15), radius: 8, y: 6)
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear {
                        stageSize = g.size
                        lastTouch = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
                    }
                    .onChange(of: g.size) { _, s in stageSize = s }
            }
        )
        .contentShape(Rectangle())
        // Where the finger is, for the pinch anchor; one finger pans when zoomed.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPinching && lastTouch != value.startLocation { lastTouch = value.startLocation }
                    if !isPinching && zoom > 1 && !edit.isActive {
                        offset = CGSize(width: steadyOffset.width + value.translation.width,
                                        height: steadyOffset.height + value.translation.height)
                    }
                }
                .onEnded { _ in
                    if !isPinching && !edit.isActive { steadyOffset = offset }
                }
        )
        .highPriorityGesture(
            MagnificationGesture()
                .onChanged { value in
                    isPinching = true
                    let newZoom = max(1, steadyZoom * value)
                    let ratio = newZoom / max(steadyZoom, 0.01)
                    let px = lastTouch.x - stageSize.width / 2
                    let py = lastTouch.y - stageSize.height / 2
                    offset = CGSize(width: px - (px - steadyOffset.width) * ratio,
                                    height: py - (py - steadyOffset.height) * ratio)
                    zoom = newZoom
                }
                .onEnded { _ in
                    isPinching = false
                    steadyZoom = max(1, zoom)
                    zoom = steadyZoom
                    steadyOffset = offset
                    if steadyZoom <= 1 { withAnimation { offset = .zero; steadyOffset = .zero } }
                }
        )
        .accessibilityIdentifier("result_page")
    }

    /// Boxes and line numbers (not touchable; the tap overlay picks the line).
    private var boxesOverlay: some View {
        GeometryReader { g in
            let sx = imageSize.width > 0 ? g.size.width / imageSize.width : 0
            let sy = imageSize.height > 0 ? g.size.height / imageSize.height : 0
            let shown = visibleLines
            let rects = shown.map { line in
                let r = line.detection.rect
                return CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
            }
            if showBoxes && !edit.isActive {
                // Divided by the zoom so lines keep their on-screen thickness when zoomed.
                let lineWidth = LineTagLayout.boxLineWidth(for: rects) / zoom
                ForEach(Array(rects.enumerated()), id: \.offset) { position, rect in
                    let on = selected == shown[position].index
                    let color = LOColor.box(position)
                    Rectangle()
                        .fill(color.opacity(on ? 0.28 : 0.08))
                        .overlay(Rectangle().stroke(color, lineWidth: on ? lineWidth * 2 : lineWidth))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                // Numbers sit at the start of each line, outside the box, so they never hide the first characters.
                ForEach(Array(LineTagLayout.frames(for: rects, in: CGRect(origin: .zero, size: g.size)).enumerated()),
                        id: \.offset) { position, tag in
                    let on = selected == shown[position].index
                    Text("\(position + 1)")
                        .font(.system(size: tag.height * 0.75, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .frame(width: tag.width, height: tag.height)
                        .background(Capsule().fill(LOColor.aiFill))
                        .overlay(Capsule().stroke(Color.white, lineWidth: max(0.5, tag.height / 16)))
                        .opacity(on ? 1 : 0.85)
                        .fixedSize()
                        .position(x: tag.midX, y: tag.midY)
                        .zIndex(on ? 1 : 0)
                }
            }
        }
    }

    /// One tap picks the line under the finger; two taps zoom in at that point, or back out.
    private var tapOverlay: some View {
        GeometryReader { g in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    ExclusiveGesture(SpatialTapGesture(count: 2), SpatialTapGesture(count: 1))
                        .onEnded { value in
                            switch value {
                            case .first(let double):
                                toggleZoom(at: double.location)
                            case .second(let tap):
                                guard showBoxes, imageSize.width > 0 else { return }
                                let s = g.size.width / imageSize.width
                                let point = CGPoint(x: tap.location.x / s, y: tap.location.y / s)
                                let shown = visibleLines
                                if let hit = BoxEditGeometry.hitBox(at: point, in: shown.map(\.detection.rect)) {
                                    select(shown[hit].index)
                                } else {
                                    withAnimation(.easeOut(duration: 0.15)) { selected = nil }
                                }
                            }
                        }
                )
        }
    }

    /// Double tap: back to the whole page when zoomed, otherwise 3× around the tapped point.
    private func toggleZoom(at location: CGPoint) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if zoom > 1 {
                zoom = 1; steadyZoom = 1
                offset = .zero; steadyOffset = .zero
            } else {
                let z: CGFloat = 3
                let px = location.x - stageSize.width / 2
                let py = location.y - stageSize.height / 2
                offset = CGSize(width: px - px * z, height: py - py * z)
                steadyOffset = offset
                zoom = z; steadyZoom = z
            }
        }
    }

    // MARK: Tools under the page

    private var pageTools: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showBoxes.toggle() }
            } label: {
                Label(String(localized: "boxes_toggle", defaultValue: "枠"),
                      systemImage: showBoxes ? "rectangle.dashed" : "rectangle.slash")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .opacity(showBoxes ? 1 : 0.6)
            }
            .buttonStyle(.loGlass)
            .accessibilityAddTraits(showBoxes ? [.isSelected] : [])
            .accessibilityIdentifier("boxes_toggle")

            Button(action: beginEditing) {
                Label(String(localized: "box_edit_enter", defaultValue: "枠を直す"),
                      systemImage: "rectangle.and.pencil.and.ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.loGlass)
            .accessibilityIdentifier("box_edit_enter")

            Spacer()
        }
    }

    // MARK: Summary

    private var summary: some View {
        let shown = visibleLines.map(\.detection)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(result.engine.title, systemImage: result.engine.symbol)
                .font(.mincho(15, relativeTo: .subheadline, bold: true))
                .foregroundColor(LOColor.ink)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 4)
            stat(String(localized: "result_lines", defaultValue: "\(shown.count) 行"))
            stat(String(localized: "result_chars", defaultValue: "\(combinedText.count) 字"))
            stat(String(format: String(localized: "result_seconds", defaultValue: "%.1f 秒"), result.seconds))
        }
        .overlay(alignment: .bottom) { LOColor.rule.frame(height: 1).offset(y: 8) }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundColor(LOColor.inkSecondary)
    }

    // MARK: Confidence

    private var hiddenCount: Int { detections.count - visibleLines.count }

    private var confidenceControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(String(localized: "confidence_label", defaultValue: "確信度"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(LOColor.ink)
                Slider(value: $threshold, in: ConfidenceFilter.range, step: 0.05)
                    .tint(LOColor.ai)
                    .accessibilityLabel(Text(String(localized: "confidence_label", defaultValue: "確信度")))
                    .accessibilityIdentifier("confidence_slider")
                Text(ConfidenceFilter.percentText(threshold))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(LOColor.ink)
                    .frame(minWidth: 44, alignment: .trailing)
                    .accessibilityIdentifier("confidence_value")
            }
            Text(hiddenCount > 0
                 ? String(format: String(localized: "confidence_hint_hidden", defaultValue: "上げると自信のない枠から隠れます。いま %d 行を隠しています"), hiddenCount)
                 : String(localized: "confidence_hint", defaultValue: "上げると自信のない枠から隠れます。表示だけの変更です"))
                .font(.caption)
                .foregroundColor(LOColor.inkSecondary)
                .accessibilityIdentifier("confidence_hint")
        }
    }

    // MARK: Lines

    private var lines: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if detections.isEmpty && !edit.isActive {
                        Text(String(localized: "result_empty", defaultValue: "文字が見つかりませんでした。別の方式で読み直すと読めることがあります。"))
                            .font(.mincho(16))
                            .foregroundColor(LOColor.inkSecondary)
                            .padding(24)
                    }
                    ForEach(Array(visibleLines.enumerated()), id: \.element.index) { position, line in
                        let index = line.index
                        LineRow(number: position + 1, colorIndex: position, text: line.detection.text,
                                selected: index == selected,
                                pending: edit.editor?.items.indices.contains(index) == true
                                    && edit.editor?.items[index].needsReread == true,
                                editable: !edit.isActive,
                                onEdit: { startEditing(index) })
                            .id(index)
                            .onTapGesture { select(index) }
                            .onLongPressGesture { if !edit.isActive { startEditing(index) } }
                            .accessibilityIdentifier("detection_row_\(index)")
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, edit.isActive ? 24 : 96)
            }
            .onChange(of: selected) { _, i in
                if let i { withAnimation(LOMotion.spring(reduceMotion: reduceMotion)) { proxy.scrollTo(i, anchor: .center) } }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: onNew) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(String(localized: "new_image", defaultValue: "次の画像"))
                        .font(.body.weight(.bold))
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
            }
            .buttonStyle(.loGlass)

            Button {
                UIPasteboard.general.string = copyText
                LOHaptics.notify(.success)
                withAnimation(.easeOut(duration: 0.2)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? String(localized: "copied", defaultValue: "コピーしました")
                                : String(localized: "copy_all", defaultValue: "全文をコピー"))
                        .font(.mincho(18, relativeTo: .headline, bold: true))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.loProminent)
            .disabled(copyText.isEmpty)
            .accessibilityIdentifier("copy_button")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .background(
            LinearGradient(stops: [.init(color: LOColor.washi.opacity(0), location: 0),
                                   .init(color: LOColor.washi, location: 0.4),
                                   .init(color: LOColor.washi, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }

    // MARK: Seal

    /// 読 seal pressed when the reading finishes: 1.3 → 1.0, about 250 ms, then fades.
    /// With Reduce Motion it only fades in.
    @ViewBuilder private var completionStamp: some View {
        if stampPhase > 0 {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LOColor.aiFill)
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)
                    .opacity(stampPhase == 2 ? 0.3 : 0)
                    .scaleEffect(stampPhase == 2 ? 1.2 : 1)
                LOSeal(size: 56)
            }
            .scaleEffect(stampPhase == 1 && !reduceMotion ? 1.3 : 1)
            .opacity(stampPhase == 1 ? (reduceMotion ? 0 : 0.5) : (stampPhase == 4 ? 0 : 1))
            .padding(10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func playStampIfNeeded() {
        guard playStamp, stampPhase == 0 else { return }
        stampPhase = 1
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.12)) { stampPhase = 2 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.13)) { stampPhase = 3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.4)) { stampPhase = 4 }
        }
    }

    // MARK: Editing a line's text

    private func startEditing(_ index: Int) {
        guard detections.indices.contains(index) else { return }
        editText = detections[index].text
        editingLine = EditingLine(index: index)
    }

    private func editSheet(_ index: Int) -> some View {
        NavigationStack {
            TextEditor(text: $editText)
                .font(.mincho(18))
                .scrollContentBackground(.hidden)
                .padding()
                .background(LOColor.washi)
                .navigationTitle(String(localized: "edit_detection_title", defaultValue: "テキストを編集"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "edit_cancel", defaultValue: "キャンセル")) { editingLine = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "edit_save", defaultValue: "保存")) {
                            if detections.indices.contains(index) {
                                detections[index].text = editText
                                detections[index].markReaderConfirmed()
                                save()
                            }
                            editingLine = nil
                        }
                        .accessibilityIdentifier("edit_save")
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Box editing

    /// The lines on screen with their index in the full list. While editing boxes every line shows
    /// (the editor works on the whole list); otherwise lines below the confidence slider are left out.
    private var visibleLines: [(index: Int, detection: Detection)] {
        if let editor = edit.editor { return editor.detections.enumerated().map { ($0.offset, $0.element) } }
        return ConfidenceFilter.visible(detections, threshold: threshold)
    }

    private var combinedText: String { ConfidenceFilter.text(detections, threshold: threshold) }

    /// Nothing to copy yet on the translation tab: the bar would cover the "translate" button.
    private var hidesBottomBar: Bool { tab == .translation && (translatedText ?? "").isEmpty }

    /// What "copy" copies: the text of the tab on screen.
    private var copyText: String { tab == .translation ? (translatedText ?? "") : combinedText }

    // MARK: Translation (on-device AI only, from KotenOCR)

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            Text(String(localized: "tab_text", defaultValue: "読み取り結果")).tag(ResultTab.text)
            Text(String(localized: "tab_translation", defaultValue: "現代語訳")).tag(ResultTab.translation)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("result_tab")
    }

    private var translationPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isTranslating {
                    // Soft light passes over placeholder lines while the model writes.
                    VStack(alignment: .leading, spacing: 14) {
                        ShimmerLine(widthFraction: 0.92)
                        ShimmerLine(widthFraction: 0.8)
                        ShimmerLine(widthFraction: 0.86)
                        Text(String(localized: "translating", defaultValue: "翻訳中..."))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(LOColor.inkSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .transition(.opacity)
                } else if let translated = translatedText, !translated.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button(action: startTranslation) {
                                Label(String(localized: "retranslate_button", defaultValue: "訳し直す"),
                                      systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 40)
                            }
                            .buttonStyle(.loGlass)
                            .accessibilityIdentifier("retranslate_button")
                            Spacer()
                        }
                        Text(translated)
                            .font(.mincho(17, relativeTo: .body))
                            .lineSpacing(8)
                            .foregroundColor(LOColor.ink)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("translation_text")
                        Text(String(localized: "translation_disclaimer", defaultValue: "端末内の AI による訳と解説です。誤りが含まれることがあります。"))
                            .font(.caption)
                            .foregroundColor(LOColor.inkSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }

                if let error = translationError {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(LOColor.danger)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("translation_error")
                }

                if translatedText == nil && !isTranslating {
                    VStack(spacing: 12) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(LOColor.inkSecondary)
                            .accessibilityHidden(true)
                        Text(String(localized: "translation_empty", defaultValue: "現代語訳がまだありません"))
                            .font(.mincho(17, relativeTo: .body))
                            .foregroundColor(LOColor.inkSecondary)
                        Text(String(localized: "translation_on_device_note", defaultValue: "端末内の AI で訳します。文字は端末の外に送りません。"))
                            .font(.caption)
                            .foregroundColor(LOColor.inkSecondary)
                            .multilineTextAlignment(.center)
                        Button(action: startTranslation) {
                            Label(String(localized: "translate_button", defaultValue: "現代語訳"), systemImage: "sparkles")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .frame(minHeight: 48)
                        }
                        .buttonStyle(.loProminent)
                        .disabled(combinedText.isEmpty)
                        .accessibilityIdentifier("translate_button")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
            .padding(.bottom, 96)
            .animation(.easeInOut(duration: 0.2), value: isTranslating)
        }
    }

    private func startTranslation() {
        // Say why up front instead of starting a request that cannot run on this device.
        let status = TranslationService.localAIStatus
        guard status == .available else {
            translationError = status.message
            return
        }
        isTranslating = true
        translationError = nil
        let text = combinedText
        Task {
            do {
                let translated = try await TranslationService.shared.translate(text: text)
                await MainActor.run {
                    translatedText = translated
                    isTranslating = false
                    if let id = historyItemID {
                        HistoryManager.shared.updateTranslation(for: id, translatedText: translated)
                    }
                }
            } catch {
                await MainActor.run {
                    translationError = error.localizedDescription
                    isTranslating = false
                }
            }
        }
    }

    private func beginEditing() {
        showBoxes = true
        edit.begin(detections: detections, imageSize: imageSize, selected: selected)
    }

    private func cancelEditing() {
        edit.cancel()
        selected = nil
    }

    private func startReread() {
        Task { await edit.reread(engine: result.engine, recognizer: recognizer, image: result.image) }
    }

    /// Done: reads any boxes still waiting, then keeps the lines and writes them to History.
    private func finishEditing() {
        Task {
            if (edit.editor?.pendingCount ?? 0) > 0 {
                let ok = await edit.reread(engine: result.engine, recognizer: recognizer, image: result.image)
                if !ok { return }
            }
            guard let edited = edit.finish() else { return }
            detections = edited
            selected = nil
            save()
        }
    }

    private func save() {
        if let id = historyItemID { HistoryManager.shared.updateDetections(id: id, detections: detections) }
    }

    private func select(_ i: Int) {
        LOHaptics.impact(.light)
        withAnimation(.easeOut(duration: 0.15)) { selected = (selected == i) ? nil : i }
    }
}

private struct EditingLine: Identifiable {
    let index: Int
    var id: Int { index }
}

/// One recognised line: a coloured number (matching its box), the text in Mincho, and a pencil.
private struct LineRow: View {
    let number: Int
    let colorIndex: Int
    let text: String
    let selected: Bool
    /// The box was changed and waits to be read again.
    let pending: Bool
    let editable: Bool
    let onEdit: () -> Void

    var body: some View {
        let color = LOColor.box(colorIndex)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundColor(color)
                .frame(minWidth: 22, alignment: .trailing)
                .accessibilityHidden(true)
            Text(text.isEmpty ? "—" : text)
                .font(.mincho(17))
                .foregroundColor(text.isEmpty || pending ? LOColor.inkSecondary : LOColor.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if pending {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundColor(LOColor.ai)
                    .accessibilityLabel(Text(String(localized: "box_edit_pending", defaultValue: "再認識が必要")))
            }
            if editable {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundColor(LOColor.inkSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(String(localized: "edit_text", defaultValue: "テキスト編集")))
                .accessibilityIdentifier("edit_detection_\(number - 1)")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, editable ? 8 : 20)
        .padding(.vertical, editable ? 2 : 9)
        .background(
            Rectangle()
                .fill(color.opacity(selected ? 0.14 : 0))
                .overlay(alignment: .leading) { color.frame(width: selected ? 3 : 0) }
        )
        .overlay(alignment: .bottom) { LOColor.rule.opacity(0.5).frame(height: 0.5).padding(.leading, 54) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(number): \(text)"))
        .accessibilityAction(named: Text(String(localized: "edit_text", defaultValue: "テキスト編集"))) {
            if editable { onEdit() }
        }
    }
}

/// A written export file. Identifiable so a sheet can present it.
struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet for files (ShareLink cannot wait for a file that is written on tap).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum ResultTab: Hashable {
    case text
    case translation
}

/// A placeholder line with soft light passing over it (1.2 s), shown while translating.
private struct ShimmerLine: View {
    let widthFraction: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(LOColor.mount)
                .overlay {
                    if !reduceMotion {
                        LinearGradient(colors: [.clear, LOColor.washiCard.opacity(0.9), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width)
                    }
                }
                .clipShape(Capsule())
                .frame(width: geo.size.width * widthFraction)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}
