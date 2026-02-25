import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm: SessionsViewModel
    @State private var showingCreate = false
    @State private var navigateToSessionId: String?

    init(api: APIClient) {
        _vm = StateObject(wrappedValue: SessionsViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.sessions.isEmpty {
                    ProgressView("Loading sessions…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "terminal",
                        description: Text("Start a Claude Code session from your machine")
                    )
                } else {
                    List {
                        ForEach(vm.sessions) { session in
                            NavigationLink(value: session) {
                                SessionRowView(session: session)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await vm.delete(session) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    Task { await vm.archive(session) }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                if session.active {
                                    Button {
                                        Task { await vm.abort(session) }
                                    } label: {
                                        Label("Stop", systemImage: "stop.circle")
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        appState.logout()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationDestination(for: Session.self) { session in
                ChatView(api: appState.apiClient!, sessionId: session.id)
            }
            .sheet(isPresented: $showingCreate) {
                CreateSessionView(api: appState.apiClient!) { sessionId in
                    navigateToSessionId = sessionId
                    Task { await vm.load() }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { navigateToSessionId != nil },
                set: { if !$0 { navigateToSessionId = nil } }
            )) {
                if let sessionId = navigateToSessionId {
                    ChatView(api: appState.apiClient!, sessionId: sessionId)
                }
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - Row

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator dot
            Circle()
                .fill(session.active ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if let path = session.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    if session.thinking {
                        Label("Thinking", systemImage: "cpu")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    let pending = session.pendingRequests.count
                    if pending > 0 {
                        Label("\(pending) permission\(pending == 1 ? "" : "s")", systemImage: "exclamationmark.shield")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(RelativeDateTimeFormatter().localizedString(
                        for: Date(timeIntervalSince1970: session.activeAt / 1000),
                        relativeTo: .now))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
