import SwiftUI

@main
struct HapiClientApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var fontSettings = FontSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(fontSettings)
        }
        .onChange(of: scenePhase) { _, newPhase in
            appState.handleScenePhase(newPhase)
        }
    }
}
