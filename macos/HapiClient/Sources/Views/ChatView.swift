import SwiftUI

struct ChatView: View {
    @StateObject private var vm: ChatViewModel
    @EnvironmentObject var appState: AppState
    @ObservedObject private var fs = FontSettings.shared
    @State private var inputText = ""
    @State private var showingSettings = false
    @State private var showingFilePicker = false
    @State private var showSlashSuggestions = false
    @State private var slashQuery = ""
    @State private var selectedCommandIndex = 0
    @State private var suppressSlashDetection = false
    @State private var isTargetedForDrop = false
    @FocusState private var inputFocused: Bool

    init(api: APIClient, store: LocalStore, syncCoordinator: SyncCoordinator, sessionId: String) {
        _vm = StateObject(wrappedValue: ChatViewModel(
            api: api, store: store, syncCoordinator: syncCoordinator, sessionId: sessionId
        ))
    }

    private var sendDisabled: Bool {
        (inputText.isEmpty && vm.attachments.isEmpty) ||
        vm.isSending ||
        vm.attachments.contains { $0.isUploading }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Permission banner
            if let session = vm.session, !session.pendingRequests.isEmpty {
                PermissionBannerView(
                    requests: session.pendingRequests,
                    onApprove: { id in Task { await vm.approve(requestId: id) } },
                    onDeny:    { id in Task { await vm.deny(requestId: id) } }
                )
            }

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if vm.hasMore {
                            Button {
                                Task { await vm.loadOlder() }
                            } label: {
                                if vm.isLoadingOlder {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Load older messages")
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }

                        ForEach(vm.messages) { message in
                            MessageBubbleView(message: message)
                                .overlay(alignment: .bottomTrailing) {
                                    if let status = message.status {
                                        switch status {
                                        case .sending:
                                            ProgressView()
                                                .scaleEffect(0.5)
                                                .padding(4)
                                        case .failed:
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                                .padding(4)
                                        case .sent:
                                            EmptyView()
                                        }
                                    }
                                }
                                .id(message.id)
                        }

                        Color.clear.frame(height: 1).id("bottom_anchor")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .defaultScrollAnchor(.bottom)
                .onChange(of: vm.scrollToBottomTrigger) { _, _ in
                    withAnimation { proxy.scrollTo("bottom_anchor", anchor: .bottom) }
                }
                .onChange(of: vm.preserveScrollId) { _, id in
                    if let id {
                        proxy.scrollTo(id, anchor: .top)
                        vm.preserveScrollId = nil
                    }
                }
            }

            Divider()

            // Input area
            inputArea
        }
        .overlay {
            if isTargetedForDrop {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(Color.blue.opacity(0.05))
                    .padding(4)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        await vm.addAttachment(url: url)
                    }
                }
            }
            return true
        }
        .toolbar {
            ToolbarItemGroup {
                ConnectionDot(
                    isConnected: vm.isConnected,
                    isThinking: vm.session?.thinking == true,
                    hasPendingRequests: !(vm.session?.pendingRequests.isEmpty ?? true),
                    isSending: vm.isSending
                )

                Spacer()

                if vm.session?.active == true {
                    Button {
                        Task { await vm.abort() }
                    } label: {
                        if vm.isAborting {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Label("Stop Agent", systemImage: "stop.circle")
                        }
                    }
                    .disabled(vm.isAborting)
                    .help("Stop the running agent")
                }

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Session Settings")
                .popover(isPresented: $showingSettings) {
                    SessionSettingsPopover(
                        currentPermissionMode: vm.session?.permissionMode,
                        currentModelMode: vm.session?.modelMode,
                        onSetPermissionMode: { mode in Task { await vm.setPermissionMode(mode) } },
                        onSetModelMode: { model in Task { await vm.setModelMode(model) } }
                    )
                }
            }
        }
        .navigationTitle(vm.session?.displayName ?? "Chat")
        .navigationSubtitle(vm.session?.path ?? "")
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    Task { await vm.addAttachment(url: url) }
                }
            }
        }
        .task {
            await vm.load()
            vm.startPolling()
            await vm.loadSlashCommands()
        }
        .onDisappear {
            vm.unload()
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 6) {
            // Connection status
            ConnectionStatusBar(
                isConnected: vm.isConnected,
                isThinking: vm.session?.thinking == true,
                hasPendingRequests: !(vm.session?.pendingRequests.isEmpty ?? true),
                isSending: vm.isSending
            )

            // Attachment previews
            if !vm.attachments.isEmpty {
                AttachmentPreviewRow(
                    attachments: vm.attachments,
                    onRemove: { id in Task { await vm.removeAttachment(id: id) } }
                )
            }

            // Slash command popup — kept in hierarchy to avoid layout thrashing
            slashPopup

            // Input row
            HStack(alignment: .center, spacing: 8) {
                // Attach button
                Button {
                    showingFilePicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Attach File")

                // Text input
                TextField("Message… (Cmd+Enter to send)", text: $inputText, axis: .vertical)
                    .font(fs.bodyFont)
                    .textFieldStyle(.plain)
                    .lineLimit(1...12)
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .focused($inputFocused)
                    .onChange(of: inputText) { _, newValue in
                        if suppressSlashDetection {
                            suppressSlashDetection = false
                            return
                        }
                        if newValue.hasPrefix("/") && !newValue.contains(" ") && !newValue.contains("\n") {
                            slashQuery = String(newValue.dropFirst())
                            showSlashSuggestions = true
                            selectedCommandIndex = 0
                        } else {
                            showSlashSuggestions = false
                        }
                    }
                    .onKeyPress(.return) {
                        if showSlashSuggestions {
                            confirmSlashSelection()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.tab) {
                        if showSlashSuggestions {
                            confirmSlashSelection()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if showSlashSuggestions {
                            selectedCommandIndex = max(0, selectedCommandIndex - 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if showSlashSuggestions {
                            let count = vm.filteredCommands(for: slashQuery).count
                            selectedCommandIndex = min(count - 1, selectedCommandIndex + 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if showSlashSuggestions {
                            showSlashSuggestions = false
                            return .handled
                        }
                        return .ignored
                    }

                // Send button (Cmd+Enter)
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: vm.isSending ? "ellipsis.circle" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(sendDisabled ? .gray : .blue)
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (Cmd+Enter)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var slashPopup: some View {
        let commands = showSlashSuggestions ? vm.filteredCommands(for: slashQuery) : []
        if !commands.isEmpty {
            SlashCommandPopup(
                commands: commands,
                selectedIndex: selectedCommandIndex,
                onSelect: { cmd in
                    suppressSlashDetection = true
                    inputText = "/\(cmd.name)"
                    showSlashSuggestions = false
                }
            )
            .transition(.opacity)
        }
    }

    private func confirmSlashSelection() {
        let commands = vm.filteredCommands(for: slashQuery)
        guard !commands.isEmpty else { return }
        let idx = min(selectedCommandIndex, commands.count - 1)
        suppressSlashDetection = true
        inputText = "/\(commands[idx].name)"
        showSlashSuggestions = false
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        showSlashSuggestions = false
        Task { await vm.executeCommand(text) }
    }
}

// MARK: - Permission Banner

struct PermissionBannerView: View {
    let requests: [String: AgentStateRequest]
    let onApprove: (String) -> Void
    let onDeny: (String) -> Void

    var body: some View {
        let requestIds = Array(requests.keys)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(requestIds, id: \.self) { requestId in
                if let req = requests[requestId] {
                    PermissionRequestCard(
                        req: req,
                        onApprove: { onApprove(requestId) },
                        onDeny: { onDeny(requestId) }
                    )
                    if requestId != requestIds.last {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
        }
        .background(Color.orange.opacity(0.06))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.orange.opacity(0.5)).frame(height: 2)
        }
    }
}

private struct PermissionRequestCard: View {
    let req: AgentStateRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    private var toolIcon: String {
        switch req.tool.lowercased() {
        case "bash", "shell": return "terminal"
        case "read": return "doc.text"
        case "write", "edit": return "pencil.line"
        case "glob": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        case "agent": return "person.2"
        case "task": return "arrow.triangle.branch"
        default: return "wrench.and.screwdriver"
        }
    }

    private var toolColor: Color {
        switch req.tool.lowercased() {
        case "bash", "shell": return .blue
        case "read": return .green
        case "write", "edit": return .orange
        case "glob", "grep": return .teal
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("Permission required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Tool info
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(toolColor.opacity(0.6))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: toolIcon)
                            .font(.caption)
                            .foregroundStyle(toolColor)
                        Text(req.tool)
                            .font(.body.bold())
                    }

                    if let summary = argumentsSummary {
                        ScrollView {
                            Text(summary)
                                .font(.callout.monospaced())
                                .foregroundStyle(.primary.opacity(0.8))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(toolColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Buttons
            HStack(spacing: 8) {
                Spacer()
                Button {
                    onDeny()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                        Text("Deny")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                Button {
                    onApprove()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                        Text("Allow")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var argumentsSummary: String? {
        guard let args = req.arguments?.value as? [String: Any] else { return nil }
        // Bash command
        if let cmd = args["command"] as? String { return cmd }
        // File path
        if let path = args["filePath"] as? String ?? args["file_path"] as? String {
            if let oldStr = args["old_string"] as? String ?? args["oldString"] as? String {
                return "\(path)\n- \(String(oldStr.prefix(200)))"
            }
            return path
        }
        // Pattern
        if let pattern = args["pattern"] as? String {
            let path = args["path"] as? String
            return path != nil ? "\(pattern) in \(path!)" : pattern
        }
        // Prompt
        if let prompt = args["prompt"] as? String { return String(prompt.prefix(200)) }
        return nil
    }
}

// MARK: - Connection Dot (toolbar)

struct ConnectionDot: View {
    let isConnected: Bool
    let isThinking: Bool
    let hasPendingRequests: Bool
    var isSending: Bool = false

    @State private var isPulsing = false

    private var shouldPulse: Bool {
        (isThinking || isSending) && !hasPendingRequests
    }

    private var color: Color {
        if hasPendingRequests { return .orange }
        if isThinking { return .blue }
        if isSending { return .yellow }
        if !isConnected { return .gray }
        return .green
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(shouldPulse ? (isPulsing ? 1.5 : 1.0) : 1.0)
            .animation(
                shouldPulse
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .help(
                hasPendingRequests ? "Permission required" :
                isThinking ? "Thinking…" :
                isSending ? "Sending…" :
                isConnected ? "Connected" : "Connecting…"
            )
    }
}

// MARK: - Session Settings Popover

struct SessionSettingsPopover: View {
    let currentPermissionMode: PermissionMode?
    let currentModelMode: ModelMode?
    let onSetPermissionMode: (String) -> Void
    let onSetModelMode: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permission Mode")
                    .font(.headline)
                ForEach(PermissionModeOption.allCases) { option in
                    Button {
                        onSetPermissionMode(option.rawValue)
                    } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if currentPermissionMode == option.rawValue ||
                                (currentPermissionMode == nil && option == .default) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.headline)
                ForEach(ModelModeOption.allCases) { option in
                    Button {
                        onSetModelMode(option.rawValue)
                    } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if currentModelMode == option.rawValue ||
                                (currentModelMode == nil && option == .default) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(width: 220)
    }
}
