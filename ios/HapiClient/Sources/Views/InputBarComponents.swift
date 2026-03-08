import SwiftUI

// MARK: - Connection Status Bar

struct ConnectionStatusBar: View {
    let isConnected: Bool
    let isThinking: Bool
    let hasPendingRequests: Bool

    @State private var isPulsing = false
    @State private var vibingWord = Self.vibingMessages.randomElement()!

    private static let vibingMessages = [
        "Accomplishing", "Baking", "Brewing", "Calculating", "Cerebrating",
        "Churning", "Clauding", "Cogitating", "Computing", "Concocting",
        "Conjuring", "Contemplating", "Cooking", "Crafting", "Creating",
        "Crunching", "Deliberating", "Divining", "Enchanting", "Envisioning",
        "Forging", "Generating", "Hatching", "Ideating", "Imagining",
        "Incubating", "Inferring", "Manifesting", "Marinating", "Mulling",
        "Musing", "Noodling", "Percolating", "Philosophising", "Pondering",
        "Processing", "Puzzling", "Ruminating", "Scheming", "Simmering",
        "Spinning", "Stewing", "Synthesizing", "Thinking", "Tinkering",
        "Transmuting", "Unravelling", "Vibing", "Whirring", "Wizarding",
        "Working", "Wrangling"
    ]

    private var statusColor: Color {
        if hasPendingRequests { return .orange }
        if isThinking { return .blue }
        if !isConnected { return .gray }
        return .green
    }

    private var statusText: String {
        if hasPendingRequests { return "permission required" }
        if isThinking { return vibingWord.lowercased() + "…" }
        if !isConnected { return "connecting…" }
        return "online"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .scaleEffect(isThinking && !hasPendingRequests ? (isPulsing ? 1.4 : 1.0) : 1.0)
                .animation(isThinking && !hasPendingRequests ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isPulsing)

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 4)
        .onAppear { isPulsing = true }
        .onChange(of: isThinking) { _, thinking in
            if thinking {
                vibingWord = Self.vibingMessages.randomElement()!
            }
        }
    }
}

// MARK: - Session Settings Sheet

struct SessionSettingsSheet: View {
    let currentPermissionMode: PermissionMode?
    let currentModelMode: ModelMode?
    let onSetPermissionMode: (String) -> Void
    let onSetModelMode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fs: FontSettings

    var body: some View {
        NavigationStack {
            List {
                Section("Permission Mode") {
                    ForEach(PermissionModeOption.allCases) { option in
                        Button {
                            onSetPermissionMode(option.rawValue)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if currentPermissionMode == option.rawValue ||
                                    (currentPermissionMode == nil && option == .default) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Model") {
                    ForEach(ModelModeOption.allCases) { option in
                        Button {
                            onSetModelMode(option.rawValue)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if currentModelMode == option.rawValue ||
                                    (currentModelMode == nil && option == .default) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Text Font") {
                    Picker("Family", selection: $fs.fontFamily) {
                        ForEach(FontSettings.availableFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }

                    HStack {
                        Text("Size")
                        Slider(value: $fs.fontSize, in: 12...24, step: 1)
                        Text("\(Int(fs.fontSize))")
                            .monospacedDigit()
                            .frame(width: 28)
                    }
                }

                Section("Code Font") {
                    Picker("Family", selection: $fs.codeFontFamily) {
                        ForEach(FontSettings.availableMonoFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }

                    HStack {
                        Text("Size")
                        Slider(value: $fs.codeFontSize, in: 10...22, step: 1)
                        Text("\(Int(fs.codeFontSize))")
                            .monospacedDigit()
                            .frame(width: 28)
                    }
                }

                Section("Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The quick brown fox jumps.")
                            .font(fs.bodyFont)
                        Text("func hello() { }")
                            .font(fs.codeFont)
                            .padding(4)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.vertical, 2)

                    Button("Reset to Defaults") {
                        fs.fontSize = 16
                        fs.codeFontSize = 14
                        fs.fontFamily = FontSettings.bundledFontName
                        fs.codeFontFamily = "Menlo"
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Session Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Slash Command Popup

struct SlashCommandPopup: View {
    let commands: [SlashCommand]
    let selectedIndex: Int
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(commands.enumerated()), id: \.offset) { idx, cmd in
                    Button { onSelect(cmd) } label: {
                        HStack(spacing: 8) {
                            Text("/\(cmd.name)")
                                .font(.subheadline.monospaced().weight(.semibold))
                                .foregroundStyle(.primary)
                            if let desc = cmd.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if cmd.source == "plugin" {
                                Text(cmd.pluginName ?? cmd.source)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundStyle(.purple)
                                    .clipShape(Capsule())
                            } else if cmd.source == "user" {
                                Text("user")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(idx == selectedIndex ? Color(.systemGray5) : .clear)
                    }
                    .buttonStyle(.plain)

                    if idx < commands.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxHeight: 260)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: -3)
    }
}

// MARK: - Attachment Preview Row

struct AttachmentPreviewRow: View {
    let attachments: [PendingAttachment]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment, onRemove: { onRemove(attachment.id) })
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct AttachmentChip: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                if let data = attachment.previewData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "doc")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Text(attachment.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            }
            .overlay {
                if attachment.isUploading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                    ProgressView()
                }
            }
            .overlay {
                if attachment.error != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white, .gray)
            }
            .offset(x: 4, y: -4)
        }
    }
}
