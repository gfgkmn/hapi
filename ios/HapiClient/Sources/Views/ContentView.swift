import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let api = appState.apiClient,
               let store = appState.localStore,
               let coordinator = appState.syncCoordinator {
                SessionsView(api: api, store: store, syncCoordinator: coordinator)
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
