import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let api = appState.apiClient {
                SessionsView(api: api)
            } else {
                LoginView()
            }
        }
        .task {
            // Auto-login on launch if credentials are saved
            await appState.tryAutoLogin()
        }
    }
}
