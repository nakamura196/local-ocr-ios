import SwiftUI
import PhotosUI
import AVFoundation

/// The app's own camera (from KotenOCR's ContentView): live preview with frame corners, a level guide,
/// the document scanner, the photo library and a one-time hint on the shutter.
/// The shutter and flash are UIKit buttons inside `CameraView`.
struct CameraScreen: View {
    @Binding var photoItem: PhotosPickerItem?
    /// A page from the shutter or the document scanner. The photo library goes through `photoItem`.
    let onCapture: (CGImage) -> Void
    let onHome: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraAuth: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showScanner = false
    @State private var tiltHintShowing = false
    @State private var showShutterCoach = false

    private var cameraDenied: Bool { cameraAuth == .denied || cameraAuth == .restricted }

    var body: some View {
        ZStack {
            CameraView(onCapture: { cg in
                CaptureMode.camera.save()
                onCapture(cg)
            })
            .ignoresSafeArea()

            // 藍 corners: where to put the page.
            ScanCorners(length: 34, radius: 4)
                .stroke(LOColor.aiBright, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .padding(.horizontal, 40)
                .padding(.top, 120)
                .padding(.bottom, 190) // stays clear of the flash and shutter buttons
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button(action: onHome) {
                        IconLabel(systemName: "house")
                    }
                    .buttonStyle(.loCameraCircle)
                    .accessibilityIdentifier("home_button")
                    .accessibilityLabel(Text(String(localized: "home_button", defaultValue: "ホーム")))

                    Button(action: onHistory) {
                        IconLabel(systemName: "clock")
                    }
                    .buttonStyle(.loCameraCircle)
                    .accessibilityIdentifier("history_button")
                    .accessibilityLabel(Text(String(localized: "history_button", defaultValue: "履歴")))

                    Spacer()

                    Button(action: onSettings) {
                        IconLabel(systemName: "gearshape")
                    }
                    .buttonStyle(.loCameraCircle)
                    .accessibilityIdentifier("settings_button")
                    .accessibilityLabel(Text(String(localized: "settings_title", defaultValue: "設定")))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Level guide above; the frame hint gives way while the tilt hint is shown.
                if !showScanner {
                    LevelGuideView(onTryScanner: DocumentScannerView.isSupported ? { openScanner() } : nil,
                                   isHintShowing: $tiltHintShowing)
                }

                if !tiltHintShowing {
                    Text(String(localized: "camera_frame_hint", defaultValue: "ページ全体を枠に入れてください"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .loGlass(.onCamera, in: Capsule())
                        .padding(.horizontal, 40)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                Spacer()

                HStack {
                    // Level with the (UIKit) shutter: its centre is 65 pt above the safe area.
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        IconLabel(systemName: "photo.on.rectangle", size: 56)
                    }
                    .buttonStyle(.loCameraCircle)
                    .accessibilityIdentifier("gallery_button")
                    .accessibilityLabel(Text(String(localized: "input_photos", defaultValue: "写真から選ぶ")))
                    Spacer()

                    if DocumentScannerView.isSupported {
                        Button(action: openScanner) {
                            IconLabel(systemName: "doc.viewfinder", size: 56)
                        }
                        .buttonStyle(.loCameraCircle)
                        .accessibilityIdentifier("scan_document_button")
                        .accessibilityLabel(Text(String(localized: "scan_document", defaultValue: "書類スキャン")))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 37)
            }

            if showShutterCoach && !cameraDenied && !showScanner {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    CoachBubble(text: String(localized: "coach_shutter", defaultValue: "ここを押して撮影"), pointer: .down)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 108)
                }
                // A touch anywhere dismisses the one-time hint.
                .contentShape(Rectangle())
                .onTapGesture { dismissShutterCoach() }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("coach_shutter")
            }

            if cameraDenied {
                CameraDeniedView(selectedPhotoItem: $photoItem, onHome: onHome)
                    .transition(LOMotion.rise(16, reduceMotion: reduceMotion))
            }
        }
        .onAppear {
            cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraDenied { LOHaptics.notify(.warning) }
            if CaptureMode.load() == .scan && DocumentScannerView.isSupported && !cameraDenied {
                // The scanner opens by itself; the shutter hint waits until the camera is really shown.
                openScanner()
            } else {
                startShutterCoachIfNeeded()
            }
        }
        .onDisappear { dismissShutterCoach() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the Settings app after allowing the camera.
            if phase == .active { cameraAuth = AVCaptureDevice.authorizationStatus(for: .video) }
        }
        .animation(.easeInOut(duration: 0.15), value: tiltHintShowing)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onScan: { cg in
                    showScanner = false
                    CaptureMode.scan.save()
                    onCapture(cg)
                },
                onCancel: {
                    showScanner = false
                    CaptureMode.camera.save()
                    startShutterCoachIfNeeded()
                }
            )
            .ignoresSafeArea()
        }
    }

    private func openScanner() {
        CaptureMode.scan.save()
        showScanner = true
    }

    /// Screenshot runs open screens themselves; the hint would cover them.
    private var isAutomatedRun: Bool {
        #if DEBUG
        let d = UserDefaults.standard
        return d.string(forKey: "demoImage") != nil || d.bool(forKey: "demoCamera")
        #else
        return false
        #endif
    }

    private func startShutterCoachIfNeeded() {
        guard !CoachMark.shutter.isShown, !isAutomatedRun, !showScanner, !cameraDenied else { return }
        withAnimation(.easeOut(duration: 0.3).delay(0.5)) { showShutterCoach = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { dismissShutterCoach() }
    }

    private func dismissShutterCoach() {
        guard showShutterCoach else { return }
        CoachMark.shutter.markShown()
        withAnimation(.easeOut(duration: 0.2)) { showShutterCoach = false }
    }
}
