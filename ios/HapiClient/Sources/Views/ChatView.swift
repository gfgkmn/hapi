import SwiftUI
import PhotosUI
import MarkdownUI

struct ChatView: View {
    @StateObject private var vm: ChatViewModel
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @State private var renameText = ""
    @State private var showingRename = false
    @State private var showingSettings = false
    @State private var showingFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showSlashSuggestions = false
    @State private var slashQuery = ""
    @State private var selectedCommandIndex = 0
    @State private var suppressSlashDetection = false

    init(api: APIClient, store: LocalStore, syncCoordinator: SyncCoordinator, sessionId: String) {
        _vm = StateObject(wrappedValue: ChatViewModel(api: api, store: store, syncCoordinator: syncCoordinator, sessionId: sessionId))
    }

    private var sendDisabled: Bool {
        (inputText.isEmpty && vm.attachments.isEmpty) || vm.isSending || vm.attachments.contains { $0.isUploading }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Permission banner
            if let session = vm.session, !session.pendingRequests.isEmpty {
                PermissionBannerView(
                    requests: session.pendingRequests,
                    onApprove: { id in Task { await vm.approve(requestId: id) } },
                    onDeny:    { id in Task { await vm.deny(requestId: id) }    }
                )
            }

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
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
                            .disabled(vm.isLoadingOlder)
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
                                                .scaleEffect(0.6)
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
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("bottom_anchor", anchor: .bottom)
                    }
                }
                .onChange(of: vm.messages.count) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation { proxy.scrollTo("bottom_anchor", anchor: .bottom) }
                    }
                }
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
            VStack(spacing: 6) {
                ConnectionStatusBar(
                    isConnected: vm.isConnected,
                    isThinking: vm.session?.thinking == true,
                    hasPendingRequests: !(vm.session?.pendingRequests.isEmpty ?? true)
                )

                if !vm.attachments.isEmpty {
                    AttachmentPreviewRow(
                        attachments: vm.attachments,
                        onRemove: { id in Task { await vm.removeAttachment(id: id) } }
                    )
                }

                if showSlashSuggestions {
                    let commands = vm.filteredCommands(for: slashQuery)
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
                    }
                }

                TextField("Message…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
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

                HStack(spacing: 16) {
                    // Attach button
                    Menu {
                        PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .screenshots])) {
                            Label("Photo Library", systemImage: "photo")
                        }
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Choose File", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }

                    // Gear (settings) button
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }

                    // Abort button
                    if vm.session?.active == true {
                        Button {
                            Task { await vm.abort() }
                        } label: {
                            if vm.isAborting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "stop.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.red)
                            }
                        }
                        .disabled(vm.isAborting)
                    }

                    Spacer()

                    // Send button
                    Button {
                        let text = inputText
                        inputText = ""
                        Task { await vm.executeCommand(text) }
                    } label: {
                        Image(systemName: vm.isSending ? "ellipsis.circle" : "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(sendDisabled ? .gray : .blue)
                    }
                    .disabled(sendDisabled)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(vm.session?.displayName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if vm.session?.active == true {
                        Button(role: .destructive) {
                            Task { await vm.abort() }
                        } label: {
                            Label("Stop Agent", systemImage: "stop.circle")
                        }
                    }
                    Button {
                        renameText = vm.session?.displayName ?? ""
                        showingRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Session", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                // Rename via API — add to ChatViewModel if needed
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingSettings) {
            SessionSettingsSheet(
                currentPermissionMode: vm.session?.permissionMode,
                currentModelMode: vm.session?.modelMode,
                onSetPermissionMode: { mode in Task { await vm.setPermissionMode(mode) } },
                onSetModelMode: { model in Task { await vm.setModelMode(model) } }
            )
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await vm.addAttachment(url: url) }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("photo_\(UUID().uuidString).jpg")
                    try? data.write(to: tempURL)
                    await vm.addAttachment(url: tempURL)
                }
                selectedPhoto = nil
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
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                Text("Permission required")
                    .font(.caption2)
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
                            .font(.callout.bold())
                    }

                    if let summary = argumentsSummary {
                        ScrollView {
                            Text(summary)
                                .font(.caption.monospaced())
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
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
        if let cmd = args["command"] as? String { return cmd }
        if let path = args["filePath"] as? String ?? args["file_path"] as? String {
            if let oldStr = args["old_string"] as? String ?? args["oldString"] as? String {
                return "\(path)\n- \(String(oldStr.prefix(200)))"
            }
            return path
        }
        if let pattern = args["pattern"] as? String {
            let path = args["path"] as? String
            return path != nil ? "\(pattern) in \(path!)" : pattern
        }
        if let prompt = args["prompt"] as? String { return String(prompt.prefix(200)) }
        return nil
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: DecryptedMessage

    var body: some View {
        Group {
            if let content = message.parsedContent {
                switch content {
                case .userText(let text):
                    UserBubble(text: text)
                case .assistantBlocks(let blocks):
                    AssistantBubbles(blocks: blocks)
                case .unknown:
                    // Hide unsupported messages (events, system, etc.) like the web does
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - User Bubble (with XML tag handling)

struct UserBubble: View {
    let text: String
    @EnvironmentObject private var fs: FontSettings

    var body: some View {
        if text.hasPrefix("<local-command-caveat>") {
            EmptyView()
        } else if text.contains("<command-name>") {
            commandBubble
        } else if text.contains("<local-command-stdout>") || text.contains("<local-command-stderr>") {
            commandOutputBubble
        } else if (text.hasPrefix("<local-") || text.hasPrefix("<command-")),
                  let stripped = Self.nonEmptyStripped(text) {
            plainBubble(stripped)
        } else {
            plainBubble(text)
        }
    }

    private var commandBubble: some View {
        HStack {
            Spacer(minLength: 60)
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.caption)
                Text(Self.extractTag(text, "command-name") ?? Self.stripTags(text))
                    .font(fs.codeFont)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.15))
            .foregroundStyle(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var commandOutputBubble: some View {
        let output = Self.extractTag(text, "local-command-stdout")
            ?? Self.extractTag(text, "local-command-stderr")
            ?? Self.stripTags(text)
        return HStack {
            Spacer(minLength: 60)
            Text(output)
                .font(fs.smallCodeFont)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func plainBubble(_ content: String) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(content)
                .font(fs.bodyFont)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private static func extractTag(_ text: String, _ tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)>(.*?)</\(tag)>",
                options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let content = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmptyStripped(_ text: String) -> String? {
        let s = stripTags(text)
        return s.isEmpty ? nil : s
    }
}

// MARK: - Assistant Bubbles

struct AssistantBubbles: View {
    let blocks: [ContentBlock]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let t):
                    MarkdownTextView(text: t)
                case .toolUse(_, let name, let input):
                    ToolUseView(name: name, input: input)
                case .toolResult(_, let content):
                    ToolResultView(content: content)
                case .reasoning(let text):
                    ReasoningBubble(text: text)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Tool Use (shows tool name + command/input)

struct ToolUseView: View {
    let name: String
    let input: Any
    @EnvironmentObject private var fs: FontSettings
    @State private var isExpanded = false

    private var toolIcon: String {
        switch name.lowercased() {
        case "bash", "shell": return "terminal"
        case "task": return "arrow.triangle.branch"
        case "read": return "doc.text"
        case "write", "edit": return "pencil.line"
        case "glob": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        default: return "wrench.and.screwdriver"
        }
    }

    private var toolColor: Color {
        switch name.lowercased() {
        case "bash", "shell": return .blue
        case "task": return .purple
        case "read": return .green
        case "write", "edit": return .orange
        case "glob", "grep": return .teal
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                // Expanded: full tool header + content
                HStack(spacing: 6) {
                    Label(name, systemImage: toolIcon)
                        .font(.caption.bold())
                        .foregroundStyle(toolColor)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
                    } label: {
                        Text("Show less")
                            .font(.caption2)
                            .foregroundStyle(toolColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)

                if let summary = inputSummary {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(toolColor.opacity(0.5))
                            .frame(width: 3)

                        Text(summary.count > 5000 ? String(summary.prefix(5000)) + "…" : summary)
                            .font(fs.codeFont)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(toolColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                // Collapsed: single line — icon + name + first line of command
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: toolIcon)
                            .font(.caption)
                            .foregroundStyle(toolColor)
                        Text(name)
                            .font(.caption.bold())
                            .foregroundStyle(toolColor)

                        if let summary = inputSummary {
                            Text(Self.firstLine(summary))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(toolColor)
                            .frame(width: 20, height: 20)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private var inputSummary: String? {
        guard let dict = input as? [String: Any] else { return nil }
        if let cmd = dict["command"] as? String { return cmd }
        if let path = dict["filePath"] as? String ?? dict["file_path"] as? String { return path }
        if let pattern = dict["pattern"] as? String { return pattern }
        return nil
    }

    private static func firstLine(_ text: String) -> String {
        // Collapse newlines + whitespace into single spaces for a dense preview
        let collapsed = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(120))
    }
}

// MARK: - Markdown Text (code blocks, tables, inline markdown)

struct MarkdownTextView: View {
    let text: String
    @EnvironmentObject private var fs: FontSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg.type {
                case .code:
                    MonoBlockView(text: seg.content)
                case .latexBlock:
                    KaTeXView(latex: seg.content, displayMode: true)
                case .latexInline:
                    KaTeXView(latex: seg.content, displayMode: false)
                case .text:
                    markdownContent(seg.content)
                }
            }
        }
    }

    @ViewBuilder
    private func markdownContent(_ str: String) -> some View {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let inlineSegs = splitByInlineLatex(trimmed)
            if inlineSegs.count == 1, case .text = inlineSegs[0].type {
                Markdown(trimmed)
                    .markdownTheme(
                        .gitHub.text {
                            FontFamily(.custom(fs.bodyFontName))
                            FontSize(CGFloat(fs.bodyFontSize))
                        }
                    )
                    .markdownTextStyle(\.code) {
                        FontFamily(.custom(fs.codeFontName))
                        FontSize(CGFloat(fs.codeFontSizeValue))
                    }
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(inlineSegs.enumerated()), id: \.offset) { _, inSeg in
                        switch inSeg.type {
                        case .latexInline:
                            KaTeXView(latex: inSeg.content, displayMode: false)
                        case .text:
                            let t = inSeg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !t.isEmpty {
                                Markdown(t)
                                    .markdownTheme(.gitHub)
                                    .markdownTextStyle(\.text) {
                                        FontSize(CGFloat(fs.bodyFontSize))
                                        FontFamily(.custom(fs.bodyFontName))
                                    }
                                    .markdownTextStyle(\.code) {
                                        FontFamily(.custom(fs.codeFontName))
                                        FontSize(CGFloat(fs.codeFontSizeValue))
                                    }
                                    .textSelection(.enabled)
                            }
                        default:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    // MARK: Segment splitting

    private enum SegType { case text, code, latexBlock, latexInline }
    private struct Segment {
        let content: String
        let type: SegType
    }

    private var segments: [Segment] {
        let afterCode = splitByCodeBlocks(text)
        var result: [Segment] = []
        for seg in afterCode {
            if case .text = seg.type {
                result.append(contentsOf: splitByDisplayLatex(seg.content))
            } else {
                result.append(seg)
            }
        }
        return result.isEmpty ? [Segment(content: text, type: .text)] : result
    }

    private func splitByCodeBlocks(_ text: String) -> [Segment] {
        guard let regex = try? NSRegularExpression(
            pattern: "```(?:[^\\n]*)\\n?(.*?)```",
            options: .dotMatchesLineSeparators
        ) else {
            return [Segment(content: text, type: .text)]
        }
        var result: [Segment] = []
        var lastEnd = text.startIndex
        let nsRange = NSRange(text.startIndex..., in: text)

        for match in regex.matches(in: text, range: nsRange) {
            guard let fullRange = Range(match.range, in: text),
                  let codeRange = Range(match.range(at: 1), in: text) else { continue }
            let before = String(text[lastEnd..<fullRange.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Segment(content: before, type: .text))
            }
            result.append(Segment(content: String(text[codeRange]), type: .code))
            lastEnd = fullRange.upperBound
        }

        let remaining = String(text[lastEnd...])
        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(Segment(content: remaining, type: .text))
        }
        return result.isEmpty ? [Segment(content: text, type: .text)] : result
    }

    private func splitByDisplayLatex(_ text: String) -> [Segment] {
        guard let regex = try? NSRegularExpression(
            pattern: "\\$\\$(.+?)\\$\\$",
            options: .dotMatchesLineSeparators
        ) else {
            return [Segment(content: text, type: .text)]
        }
        var result: [Segment] = []
        var lastEnd = text.startIndex
        let nsRange = NSRange(text.startIndex..., in: text)

        for match in regex.matches(in: text, range: nsRange) {
            guard let fullRange = Range(match.range, in: text),
                  let exprRange = Range(match.range(at: 1), in: text) else { continue }
            let before = String(text[lastEnd..<fullRange.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Segment(content: before, type: .text))
            }
            result.append(Segment(
                content: String(text[exprRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                type: .latexBlock
            ))
            lastEnd = fullRange.upperBound
        }

        let remaining = String(text[lastEnd...])
        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(Segment(content: remaining, type: .text))
        }
        return result.isEmpty ? [Segment(content: text, type: .text)] : result
    }

    private func splitByInlineLatex(_ text: String) -> [Segment] {
        guard let regex = try? NSRegularExpression(
            pattern: "(?<!\\$)\\$(?!\\$)(?!\\s)(?!\\d)(.+?)(?<!\\s)\\$(?!\\$)",
            options: []
        ) else {
            return [Segment(content: text, type: .text)]
        }
        var result: [Segment] = []
        var lastEnd = text.startIndex
        let nsRange = NSRange(text.startIndex..., in: text)

        for match in regex.matches(in: text, range: nsRange) {
            guard let fullRange = Range(match.range, in: text),
                  let exprRange = Range(match.range(at: 1), in: text) else { continue }
            let before = String(text[lastEnd..<fullRange.lowerBound])
            if !before.isEmpty {
                result.append(Segment(content: before, type: .text))
            }
            result.append(Segment(
                content: String(text[exprRange]),
                type: .latexInline
            ))
            lastEnd = fullRange.upperBound
        }

        let remaining = String(text[lastEnd...])
        if !remaining.isEmpty {
            result.append(Segment(content: remaining, type: .text))
        }
        return result.isEmpty ? [Segment(content: text, type: .text)] : result
    }
}

// MARK: - MonoBlockView (fenced code blocks in markdown)

struct MonoBlockView: View {
    let text: String
    var defaultExpanded: Bool = true
    @EnvironmentObject private var fs: FontSettings
    @State private var wordWrap = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with wrap toggle
            HStack(spacing: 6) {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { wordWrap.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "text.append")
                        Text(wordWrap ? "Wrap" : "Scroll")
                    }
                    .font(.caption2)
                    .foregroundStyle(wordWrap ? .blue : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(wordWrap ? Color.blue.opacity(0.1) : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if defaultExpanded {
                codeContent
            } else {
                DisclosureGroup {
                    codeContent.padding(.top, 4)
                } label: {
                    Text(String(text.prefix(80)).replacingOccurrences(of: "\n", with: " "))
                        .font(fs.smallCodeFont)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var codeContent: some View {
        Group {
            if wordWrap {
                Text(text)
                    .font(fs.codeFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(text)
                        .font(fs.codeFont)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }
}

// MARK: - Reasoning Bubble

struct ReasoningBubble: View {
    let text: String
    @EnvironmentObject private var fs: FontSettings
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(fs.bodyFont)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } label: {
            Label("Reasoning", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.purple)
        }
        .padding(10)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Tool Result (output)

struct ToolResultView: View {
    let content: Any
    @EnvironmentObject private var fs: FontSettings
    @State private var selectedImage: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Render any images from content blocks
            ForEach(Array(Self.extractImages(from: content).enumerated()), id: \.offset) { _, uiImage in
                Button {
                    selectedImage = uiImage
                } label: {
                    SwiftUI.Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .fullScreenCover(isPresented: Binding(
                get: { selectedImage != nil },
                set: { if !$0 { selectedImage = nil } }
            )) {
                if let img = selectedImage {
                    ImageFullScreenView(image: img)
                }
            }

            let raw = Self.extractText(from: content)
            if !raw.isEmpty {
                let parsed = Self.parsePersistedOutput(raw)
                if parsed.isPersisted {
                    // Persisted output: show compact info chip
                    DisclosureGroup {
                        if let inner = parsed.text {
                            Text(inner.count > 10000 ? String(inner.prefix(10000)) + "…" : inner)
                                .font(fs.smallCodeFont)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.caption2)
                            Text(parsed.summary ?? "Large output (stored)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color(.systemGray6).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // Normal output: smaller, dimmer, collapsed if long
                    OutputBlockView(
                        text: String(raw.prefix(10000)),
                        collapsed: raw.count > 300
                    )
                }
            }
        }
    }

    private static func extractText(from content: Any) -> String {
        if let s = content as? String { return s }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    private static func extractImages(from content: Any) -> [UIImage] {
        guard let blocks = content as? [[String: Any]] else { return [] }
        var images: [UIImage] = []
        for block in blocks {
            guard let type = block["type"] as? String, type == "image" else { continue }
            guard let source = block["source"] as? [String: Any],
                  let dataStr = source["data"] as? String,
                  let data = Data(base64Encoded: dataStr),
                  let uiImage = UIImage(data: data) else { continue }
            images.append(uiImage)
        }
        return images
    }

    private struct PersistedResult {
        let isPersisted: Bool
        let summary: String?
        let text: String?
    }

    private static func parsePersistedOutput(_ text: String) -> PersistedResult {
        // Match <persisted-output> ... </persisted-output> or just <persisted-output>...
        if text.contains("<persisted-output>") || text.contains("persisted-output") {
            // Try to extract content between tags
            if let regex = try? NSRegularExpression(
                pattern: "<persisted-output>(.*?)(?:</persisted-output>|$)",
                options: .dotMatchesLineSeparators
            ) {
                let nsRange = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: nsRange),
                   let range = Range(match.range(at: 1), in: text) {
                    let inner = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Extract summary like "Output too large (271KB). ..."
                    let summary = inner.components(separatedBy: "\n").first?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return PersistedResult(isPersisted: true, summary: summary?.isEmpty == true ? nil : summary, text: inner)
                }
            }
            // Tag present but couldn't parse inner — still treat as persisted
            let cleaned = text
                .replacingOccurrences(of: "<persisted-output>", with: "")
                .replacingOccurrences(of: "</persisted-output>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = cleaned.components(separatedBy: "\n").first
            return PersistedResult(isPersisted: true, summary: summary, text: cleaned.isEmpty ? nil : cleaned)
        }
        return PersistedResult(isPersisted: false, summary: nil, text: nil)
    }
}

// MARK: - Output Block (tool result display)

private struct OutputBlockView: View {
    let text: String
    let collapsed: Bool
    @EnvironmentObject private var fs: FontSettings
    @State private var isExpanded = false
    @State private var wordWrap = true

    /// Replace `→` arrows in `cat -n` line number prefixes with a space
    private var cleanedText: String {
        text.replacingOccurrences(of: "→", with: " ")
    }

    private var isLong: Bool {
        text.components(separatedBy: "\n").count > 4 || text.count > 300
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wrap toggle + show less (only when expanded and long)
            if isLong {
                HStack(spacing: 6) {
                    Spacer()
                    if isExpanded {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { wordWrap.toggle() }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "text.append")
                                Text(wordWrap ? "Wrap" : "Scroll")
                            }
                            .font(.caption2)
                            .foregroundStyle(wordWrap ? .blue : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(wordWrap ? Color.blue.opacity(0.1) : Color.clear)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }

            // Content
            Group {
                if isExpanded || !isLong {
                    // Full content (or short content that doesn't need collapsing)
                    if wordWrap || !isLong {
                        Text(cleanedText)
                            .font(fs.smallCodeFont)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(cleanedText)
                                .font(fs.smallCodeFont)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                } else {
                    Text(cleanedText)
                        .font(fs.smallCodeFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Image Full Screen (pinch to zoom)

private struct ImageFullScreenView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SwiftUI.Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { value in
                            lastScale = scale
                            if scale < 1.0 {
                                withAnimation { scale = 1.0; lastScale = 1.0 }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1.0 {
                            scale = 1.0; lastScale = 1.0
                            offset = .zero; lastOffset = .zero
                        } else {
                            scale = 2.5; lastScale = 2.5
                        }
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }
}
