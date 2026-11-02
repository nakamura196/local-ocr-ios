import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Main screen: pick an engine, bring in an image, read it.
struct ContentView: View {
    @EnvironmentObject var store: ModelStore
    @EnvironmentObject var recognizer: Recognizer
    @AppStorage("engine") private var engineRaw = EngineKind.vision.rawValue

    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var showModels = false
    @State private var image: CGImage?
    @State private var result: PageResult?
    @State private var errorMessage: String?

    private var engine: EngineKind { EngineKind(rawValue: engineRaw) ?? .vision }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let result {
                    ResultView(result: result)
                } else if let image {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    emptyState
                }
                Divider()
                bottomBar
            }
            .navigationTitle("Local OCR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showModels = true } label: {
                        Label(String(localized: "models_title", defaultValue: "読み取りモデル"), systemImage: "square.and.arrow.down.on.square")
                    }
                }
                if let result {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: result.text) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
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
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in
                    if let picked { setImage(picked) }
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
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if store.status[engine] != .installed { engineRaw = EngineKind.vision.rawValue }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.viewfinder").font(.system(size: 56)).foregroundStyle(.secondary)
            Text(String(localized: "empty_title", defaultValue: "画像を選ぶと、この端末の中で文字を読み取ります"))
                .font(.headline).multilineTextAlignment(.center)
            if store.installedEngines.count <= 1 {
                Button { showModels = true } label: {
                    Label(String(localized: "empty_get_models", defaultValue: "くずし字・活字のモデルを入れる"),
                          systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Picker(String(localized: "engine_picker", defaultValue: "読み取り方式"), selection: $engineRaw) {
                ForEach(store.installedEngines) { kind in
                    Text(kind.title).tag(kind.rawValue)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(String(localized: "input_photos", defaultValue: "写真"), systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                Button { showFiles = true } label: {
                    Label(String(localized: "input_files", defaultValue: "ファイル"), systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: {
                        Label(String(localized: "input_camera", defaultValue: "撮影"), systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.bordered)

            Button {
                Task { await read() }
            } label: {
                HStack {
                    if recognizer.isRunning { ProgressView().tint(.white) }
                    Text(recognizer.isRunning
                         ? String(localized: "reading", defaultValue: "読み取り中…")
                         : String(localized: "read", defaultValue: "読み取る"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(image == nil || recognizer.isRunning)
        }
        .padding()
    }

    private func setImage(_ ui: UIImage) {
        image = ui.normalizedCGImage()
        result = nil
    }

    private func read() async {
        guard let image else { return }
        do {
            result = try await recognizer.run(engine, on: image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

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
