import SwiftUI

private struct ScrollNearBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatView: View {
    @StateObject private var vm: ChatViewModel
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @State private var renameText = ""
    @State private var showingRename = false

    init(api: APIClient, sessionId: String) {
        _vm = StateObject(wrappedValue: ChatViewModel(api: api, sessionId: sessionId))
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

            // Thinking indicator
            if vm.session?.thinking == true {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Agent is thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if vm.hasMore {
                            Button("Load older messages") {
                                Task { await vm.loadOlder() }
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }

                        ForEach(vm.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        // Anchor for scroll-to-bottom and near-bottom detection
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollNearBottomKey.self,
                                value: geo.frame(in: .named("chatScroll")).minY
                            )
                        }
                        .frame(height: 1)
                        .id("bottom_anchor")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .coordinateSpace(name: "chatScroll")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onPreferenceChange(ScrollNearBottomKey.self) { bottomY in
                    // If the bottom anchor is within 120pt of the scroll view's visible area
                    vm.isNearBottom = bottomY < UIScreen.main.bounds.height + 120
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if vm.isNearBottom {
                        withAnimation { proxy.scrollTo("bottom_anchor", anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Button {
                    let text = inputText
                    inputText = ""
                    Task { await vm.send(text: text) }
                } label: {
                    Image(systemName: vm.isSending ? "ellipsis.circle" : "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(inputText.isEmpty ? .gray : .blue)
                }
                .disabled(inputText.isEmpty || vm.isSending)
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
                            Task {
                                // No abort in ChatViewModel directly, handled via session action
                            }
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
        .task { await vm.load() }
        .onAppear {
            if let token = appState.apiClient.map({ _ in appState.tokenManager.jwt }) {
                vm.startSSE(token: token)
            }
        }
        .onDisappear { vm.stopSSE() }
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
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Permission required")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(req.tool)
                                .font(.callout)
                                .bold()
                        }
                        Spacer()
                        Button("Deny") { onDeny(requestId) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        Button("Approve") { onApprove(requestId) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    if requestId != requestIds.last {
                        Divider()
                    }
                }
            }
        }
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
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
                    .font(.callout.monospaced())
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
                .font(.caption.monospaced())
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
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(name, systemImage: "wrench.and.screwdriver")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let summary = inputSummary {
                MonoBlockView(text: summary, defaultExpanded: summary.count < 200)
            }
        }
        .padding(.vertical, 2)
    }

    private var inputSummary: String? {
        guard let dict = input as? [String: Any] else { return nil }
        // Bash: show command
        if let cmd = dict["command"] as? String { return cmd }
        // File operations: show path (key may be camelCased by decoder)
        if let path = dict["filePath"] as? String ?? dict["file_path"] as? String { return path }
        // Search: show pattern
        if let pattern = dict["pattern"] as? String { return pattern }
        return nil
    }
}

// MARK: - Markdown Text (code blocks, tables, inline markdown)

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg.type {
                case .code:
                    MonoBlockView(text: seg.content)
                case .table:
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(seg.content)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                case .text:
                    inlineMarkdown(seg.content)
                }
            }
        }
    }

    @ViewBuilder
    private func inlineMarkdown(_ str: String) -> some View {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let attr = try? AttributedString(
                markdown: trimmed,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attr).font(.body)
            } else {
                Text(trimmed).font(.body)
            }
        }
    }

    // MARK: Segment splitting

    private enum SegType { case text, code, table }
    private struct Segment {
        let content: String
        let type: SegType
    }

    private var segments: [Segment] {
        // 1. Split by fenced code blocks
        let afterCode = splitByCodeBlocks(text)
        // 2. Split remaining text segments by markdown tables
        var result: [Segment] = []
        for seg in afterCode {
            if seg.type == .code {
                result.append(seg)
            } else {
                result.append(contentsOf: splitByTables(seg.content))
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

    private func splitByTables(_ text: String) -> [Segment] {
        let lines = text.components(separatedBy: "\n")
        var result: [Segment] = []
        var tableLines: [String] = []
        var textLines: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                if !textLines.isEmpty {
                    let joined = textLines.joined(separator: "\n")
                    if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.append(Segment(content: joined, type: .text))
                    }
                    textLines = []
                }
                tableLines.append(line)
            } else {
                if !tableLines.isEmpty {
                    result.append(Segment(content: tableLines.joined(separator: "\n"), type: .table))
                    tableLines = []
                }
                textLines.append(line)
            }
        }
        if !tableLines.isEmpty {
            result.append(Segment(content: tableLines.joined(separator: "\n"), type: .table))
        }
        if !textLines.isEmpty {
            let joined = textLines.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Segment(content: joined, type: .text))
            }
        }
        return result.isEmpty ? [Segment(content: text, type: .text)] : result
    }
}

// MARK: - MonoBlockView (shared monospace block with wrap toggle)

struct MonoBlockView: View {
    let text: String
    var font: Font = .callout.monospaced()
    var defaultExpanded: Bool = true
    @State private var wrapText = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if defaultExpanded {
                content
            } else {
                // Collapsible for long content
                DisclosureGroup {
                    content.padding(.top, 4)
                } label: {
                    Text(String(text.prefix(60)).replacingOccurrences(of: "\n", with: " "))
                        .font(font)
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

    private var content: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                wrapText.toggle()
            } label: {
                Image(systemName: wrapText ? "arrow.left.and.right" : "text.justify.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Group {
                if wrapText {
                    Text(text)
                        .font(font)
                        .textSelection(.enabled)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(text)
                            .font(font)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Reasoning Bubble

struct ReasoningBubble: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.callout)
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

// MARK: - Tool Result (expandable)

struct ToolResultView: View {
    let content: Any

    var body: some View {
        let text = Self.extractText(from: content)
        if !text.isEmpty {
            MonoBlockView(
                text: String(text.prefix(10000)),
                font: .caption.monospaced(),
                defaultExpanded: text.count < 300
            )
        }
    }

    private static func extractText(from content: Any) -> String {
        if let s = content as? String { return s }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }
}
