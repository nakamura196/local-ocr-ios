import SwiftUI

@main
struct LocalOCRApp: App {
    @StateObject private var store = ModelStore()
    @StateObject private var recognizer = Recognizer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(recognizer)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    recognizer.handleMemoryWarning()
                }
        }
    }
}
