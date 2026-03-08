import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let api = appState.apiClient,
               let store = appState.localStore,
               let coordinator = appState.syncCoordinator {
                MainView(api: api, store: store, syncCoordinator: coordinator)
            } else {
                LoginView()
            }
        }
        .task {
            await appState.tryAutoLogin()
        }
    }
}

// MARK: - Main View (Sidebar + Detail)

struct MainView: View {
    let api: APIClient
    let store: LocalStore
    let syncCoordinator: SyncCoordinator

    @EnvironmentObject var appState: AppState
    @State private var selectedSessionId: String?
    @State private var showingCreate = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @StateObject private var sessionsVM: SessionsViewModel

    init(api: APIClient, store: LocalStore, syncCoordinator: SyncCoordinator) {
        self.api = api
        self.store = store
        self.syncCoordinator = syncCoordinator
        _sessionsVM = StateObject(wrappedValue: SessionsViewModel(
            api: api, store: store, syncCoordinator: syncCoordinator
        ))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                vm: sessionsVM,
                selectedSessionId: $selectedSessionId
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New Session (Cmd+N)")

                    Button {
                        Task { await sessionsVM.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh (Cmd+R)")

                    Spacer()

                    Button {
                        appState.logout()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .help("Logout")
                }
            }
        } detail: {
            if let sessionId = selectedSessionId {
                ChatView(
                    api: api,
                    store: store,
                    syncCoordinator: syncCoordinator,
                    sessionId: sessionId
                )
                .id(sessionId)
            } else {
                EmptyDetailView()
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateSessionView(api: api) { sessionId in
                selectedSessionId = sessionId
                Task { await sessionsVM.load() }
            }
            .frame(width: 450, height: 520)
        }
        .task { await sessionsVM.load() }
    }
}

// MARK: - Empty Detail Placeholder

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a session")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Choose a session from the sidebar or create a new one with Cmd+N")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
