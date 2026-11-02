import SwiftUI

@main
struct LocalOCRApp: App {
    @StateObject private var store = ModelStore()
    @StateObject private var recognizer = Recognizer()
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(recognizer)
                .preferredColorScheme((AppTheme(rawValue: appThemeRaw) ?? .system).colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    recognizer.handleMemoryWarning()
                }
        }
    }
}
