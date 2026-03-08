import SwiftUI

struct SidebarView: View {
    @ObservedObject var vm: SessionsViewModel
    @Binding var selectedSessionId: String?
    @State private var searchText = ""
    @State private var sessionToDelete: Session?

    private var filteredSessions: [Session] {
        if searchText.isEmpty { return vm.sessions }
        let term = searchText.lowercased()
        return vm.sessions.filter { session in
            session.displayName.lowercased().contains(term) ||
            (session.path?.lowercased().contains(term) ?? false)
        }
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.sessions.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading sessions…")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if vm.sessions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No Sessions")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Start a session from your machine or press Cmd+N")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                List(selection: $selectedSessionId) {
                    ForEach(filteredSessions) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                            .contextMenu {
                                if session.active {
                                    Button {
                                        Task { await vm.abort(session) }
                                    } label: {
                                        Label("Stop Agent", systemImage: "stop.circle")
                                    }
                                    Divider()
                                }
                                Button {
                                    Task {
                                        await vm.archive(session)
                                        if selectedSessionId == session.id {
                                            selectedSessionId = nil
                                        }
                                    }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                Button(role: .destructive) {
                                    sessionToDelete = session
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Filter sessions")
            }
        }
        .navigationTitle("Sessions")
        .alert("Delete Session?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
            Button("Delete", role: .destructive) {
                guard let session = sessionToDelete else { return }
                let wasSelected = selectedSessionId == session.id
                Task {
                    await vm.delete(session)
                    if wasSelected { selectedSessionId = nil }
                }
                sessionToDelete = nil
            }
        } message: {
            Text("This will permanently delete \"\(sessionToDelete?.displayName ?? "this session")\".")
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            // Active indicator dot
            Circle()
                .fill(session.active ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let path = session.path {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    if session.thinking {
                        Image(systemName: "cpu")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    let pending = session.pendingRequestsCount ?? 0
                    if pending > 0 {
                        Image(systemName: "exclamationmark.shield")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if let todo = session.todoProgress {
                        Text("\(todo.completed)/\(todo.total)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(RelativeDateTimeFormatter().localizedString(
                    for: Date(timeIntervalSince1970: session.activeAt / 1000),
                    relativeTo: .now))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
