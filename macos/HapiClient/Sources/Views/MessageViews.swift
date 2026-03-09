import SwiftUI
import AppKit

// MARK: - Message Bubble Router

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
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - User Bubble

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
            Spacer(minLength: 120)
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.caption)
                Text(Self.extractTag(text, "command-name") ?? Self.stripTags(text))
                    .font(fs.codeFont)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.12))
            .foregroundStyle(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var commandOutputBubble: some View {
        let output = Self.extractTag(text, "local-command-stdout")
            ?? Self.extractTag(text, "local-command-stderr")
            ?? Self.stripTags(text)
        return HStack {
            Spacer(minLength: 120)
            Text(output)
                .font(fs.smallCodeFont)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func plainBubble(_ content: String) -> some View {
        HStack {
            Spacer(minLength: 120)
            Text(content)
                .font(fs.bodyFont)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Tag helpers

    static func extractTag(_ text: String, _ tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)>(.*?)</\(tag)>",
                options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let content = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func nonEmptyStripped(_ text: String) -> String? {
        let s = stripTags(text)
        return s.isEmpty ? nil : s
    }
}

// MARK: - Assistant Bubbles

struct AssistantBubbles: View {
    let blocks: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(.horizontal, 2)
    }
}

// MARK: - Tool Use

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
        case "agent": return "person.2"
        case "todowrite", "todoread": return "checklist"
        case "webfetch", "websearch": return "globe"
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
        case "agent": return .indigo
        case "todowrite", "todoread": return .mint
        case "webfetch", "websearch": return .cyan
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tool header
            HStack(spacing: 6) {
                Image(systemName: toolIcon)
                    .font(.caption)
                    .foregroundStyle(toolColor)
                Text(name)
                    .font(.caption.bold())
                    .foregroundStyle(toolColor)

                // Show primary info inline with header
                if let brief = briefSummary {
                    Text(brief)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 6)

            // Full input content
            if let detail = detailContent {
                let isLong = detail.count > 400
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(toolColor.opacity(0.5))
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 0) {
                            if isLong && isExpanded {
                                ScrollView {
                                    Text(String(detail.prefix(20000)))
                                        .font(fs.codeFont)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                }
                                .frame(maxHeight: 400)
                            } else {
                                Text(isLong ? String(detail.prefix(400)) + "…" : detail)
                                    .font(fs.codeFont)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            }

                            if isLong {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption2)
                                        Text(isExpanded ? "Show less" : "Show all (\(detail.count) chars)")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(toolColor)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(toolColor.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 2)
    }

    /// Short description for the header line
    private var briefSummary: String? {
        guard let dict = input as? [String: Any] else { return nil }
        if let path = dict["filePath"] as? String ?? dict["file_path"] as? String { return path }
        if let pattern = dict["pattern"] as? String { return pattern }
        return nil
    }

    /// Full content to display in the detail block
    private var detailContent: String? {
        guard let dict = input as? [String: Any] else { return nil }
        // Bash/shell: show command
        if let cmd = dict["command"] as? String { return cmd }
        // Edit: show old/new strings
        if let oldStr = dict["old_string"] as? String ?? dict["oldString"] as? String {
            let newStr = dict["new_string"] as? String ?? dict["newString"] as? String ?? ""
            var result = "- " + oldStr
            if !newStr.isEmpty { result += "\n+ " + newStr }
            return result
        }
        // Write: show content
        if let content = dict["content"] as? String { return content }
        // Grep/Glob: show pattern (already in header, but show path too)
        if let pattern = dict["pattern"] as? String {
            let path = dict["path"] as? String
            return path != nil ? "\(pattern) in \(path!)" : pattern
        }
        // Agent/task: show prompt
        if let prompt = dict["prompt"] as? String { return prompt }
        if let description = dict["description"] as? String { return description }
        return nil
    }
}

// MARK: - Markdown Text

struct MarkdownTextView: View {
    let text: String
    @EnvironmentObject private var fs: FontSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg.type {
                case .code(let lang):
                    CodeBlockView(text: seg.content, language: lang)
                case .table:
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(seg.content)
                            .font(fs.codeFont)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                Text(attr)
                    .font(fs.bodyFont)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            } else {
                Text(trimmed)
                    .font(fs.bodyFont)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }
        }
    }

    // MARK: - Segment Splitting

    private enum SegType {
        case text
        case code(language: String?)
        case table
    }
    private struct Segment {
        let content: String
        let type: SegType
    }

    private var segments: [Segment] {
        let afterCode = splitByCodeBlocks(text)
        var result: [Segment] = []
        for seg in afterCode {
            if case .text = seg.type {
                result.append(contentsOf: splitByTables(seg.content))
            } else {
                result.append(seg)
            }
        }
        return result.isEmpty ? [Segment(content: text, type: .text)] : result
    }

    private func splitByCodeBlocks(_ text: String) -> [Segment] {
        guard let regex = try? NSRegularExpression(
            pattern: "```([^\\n]*)\\n?(.*?)```",
            options: .dotMatchesLineSeparators
        ) else {
            return [Segment(content: text, type: .text)]
        }
        var result: [Segment] = []
        var lastEnd = text.startIndex
        let nsRange = NSRange(text.startIndex..., in: text)

        for match in regex.matches(in: text, range: nsRange) {
            guard let fullRange = Range(match.range, in: text),
                  let langRange = Range(match.range(at: 1), in: text),
                  let codeRange = Range(match.range(at: 2), in: text) else { continue }
            let before = String(text[lastEnd..<fullRange.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Segment(content: before, type: .text))
            }
            let lang = String(text[langRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(Segment(
                content: String(text[codeRange]),
                type: .code(language: lang.isEmpty ? nil : lang)
            ))
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

// MARK: - Code Block (with language label + Copy)

struct CodeBlockView: View {
    let text: String
    var language: String? = nil
    @EnvironmentObject private var fs: FontSettings
    @State private var copied = false
    @State private var wordWrap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language + wrap toggle + copy
            HStack(spacing: 6) {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                }
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
                .help(wordWrap ? "Disable word wrap" : "Enable word wrap")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        if copied { Text("Copied").font(.caption2) }
                    }
                    .font(.caption2)
                    .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // Code content
            if wordWrap {
                codeText
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    codeText
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: text.count > 5000 ? 500 : nil)
            }
        }
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var codeText: some View {
        let display = text.count > 20000 ? String(text.prefix(20000)) : text
        return Text(display)
            .font(fs.codeFont)
            .textSelection(.enabled)
            .frame(maxWidth: wordWrap ? .infinity : nil, alignment: .leading)
            .lineSpacing(2)
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
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "brain")
                    .font(.caption)
                Text("Reasoning")
                    .font(.caption.bold())
                Text("(\(text.count) chars)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.purple)
        }
        .padding(12)
        .background(Color.purple.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Tool Result

struct ToolResultView: View {
    let content: Any
    @EnvironmentObject private var fs: FontSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Render any images from content blocks
            ForEach(Array(Self.extractImages(from: content).enumerated()), id: \.offset) { _, nsImage in
                Button {
                    ImageWindowController.show(image: nsImage)
                } label: {
                    ImageThumbnail(nsImage: nsImage, widthFraction: 0.8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }

            // Render text content
            let raw = Self.extractText(from: content)
            if !raw.isEmpty {
                let parsed = Self.parsePersistedOutput(raw)
                if parsed.isPersisted {
                    PersistedOutputView(summary: parsed.summary, text: parsed.text)
                } else {
                    OutputBlockView(
                        text: String(raw.prefix(10000)),
                        collapsed: raw.count > 300
                    )
                }
            }
        }
    }

    static func extractText(from content: Any) -> String {
        if let s = content as? String { return s }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    static func extractImages(from content: Any) -> [NSImage] {
        guard let blocks = content as? [[String: Any]] else { return [] }
        var images: [NSImage] = []
        for block in blocks {
            guard let type = block["type"] as? String, type == "image" else { continue }
            guard let source = block["source"] as? [String: Any],
                  let dataStr = source["data"] as? String,
                  let data = Data(base64Encoded: dataStr),
                  let nsImage = NSImage(data: data) else { continue }
            images.append(nsImage)
        }
        return images
    }

    struct PersistedResult {
        let isPersisted: Bool
        let summary: String?
        let text: String?
    }

    static func parsePersistedOutput(_ text: String) -> PersistedResult {
        if text.contains("<persisted-output>") || text.contains("persisted-output") {
            if let regex = try? NSRegularExpression(
                pattern: "<persisted-output>(.*?)(?:</persisted-output>|$)",
                options: .dotMatchesLineSeparators
            ) {
                let nsRange = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: nsRange),
                   let range = Range(match.range(at: 1), in: text) {
                    let inner = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let summary = inner.components(separatedBy: "\n").first?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return PersistedResult(isPersisted: true, summary: summary?.isEmpty == true ? nil : summary, text: inner)
                }
            }
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

// MARK: - Persisted Output

private struct PersistedOutputView: View {
    let summary: String?
    let text: String?
    @EnvironmentObject private var fs: FontSettings
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 10)
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption2)
                    Text(summary ?? "Large output (stored)")
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let inner = text {
                Divider().padding(.horizontal, 10)
                ScrollView {
                    Text(inner.count > 10000 ? String(inner.prefix(10000)) + "…" : inner)
                        .font(fs.smallCodeFont)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                        .padding(10)
                }
                .frame(maxHeight: 300)
            }
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Output Block

private struct OutputBlockView: View {
    let text: String
    let collapsed: Bool
    @EnvironmentObject private var fs: FontSettings
    @State private var isExpanded = false
    @State private var wordWrap = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if collapsed && !isExpanded {
                // Collapsed: preview + expand button
                HStack(spacing: 0) {
                    Text(String(text.prefix(120)).replacingOccurrences(of: "\n", with: " "))
                        .font(fs.smallCodeFont)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
                    } label: {
                        Text("Show all")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
            } else {
                // Expanded or short content
                VStack(alignment: .leading, spacing: 0) {
                    // Wrap toggle + collapse button
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
                        if collapsed {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
                            } label: {
                                Text("Show less")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)

                    if wordWrap {
                        outputText
                            .padding(10)
                    } else {
                        ScrollView(.horizontal, showsIndicators: true) {
                            outputText
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(10)
                        }
                        .frame(maxHeight: text.count > 5000 ? 400 : nil)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var outputText: some View {
        let display = text.count > 20000 ? String(text.prefix(20000)) : text
        return Text(display)
            .font(fs.smallCodeFont)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: wordWrap ? .infinity : nil, alignment: .leading)
            .lineSpacing(2)
    }
}

// MARK: - Image Window (resizable standalone NSWindow)

private struct ImageThumbnail: View {
    let nsImage: NSImage
    let widthFraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geo.size.width * widthFraction)
        }
        .aspectRatio(nsImage.size.width / max(nsImage.size.height, 1) * (1.0 / widthFraction), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private final class ImageWindowController {
    static func show(image: NSImage) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        // Start at 70% of screen size, centered
        let w = min(screenFrame.width * 0.7, image.size.width + 40)
        let h = min(screenFrame.height * 0.7, image.size.height + 40)
        let x = screenFrame.midX - w / 2
        let y = screenFrame.midY - h / 2
        let rect = NSRect(x: x, y: y, width: max(w, 400), height: max(h, 300))

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Image Preview"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let hostView = NSHostingView(rootView:
            ImagePopoverContent(image: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        window.contentView = hostView
        window.makeKeyAndOrderFront(nil)
    }
}

private struct ImagePopoverContent: View {
    let image: NSImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1.0 {
                                withAnimation { scale = 1.0; lastScale = 1.0 }
                            }
                        }
                )
                .gesture(
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
                Spacer()
                Text("Scroll to zoom  ·  Drag to pan  ·  Double-click to fit")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 8)
            }
        }
    }
}
