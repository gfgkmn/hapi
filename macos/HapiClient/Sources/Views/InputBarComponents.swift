import SwiftUI

// MARK: - Connection Status Bar

struct ConnectionStatusBar: View {
    let isConnected: Bool
    let isThinking: Bool
    let hasPendingRequests: Bool
    var isSending: Bool = false

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

    private var shouldPulse: Bool {
        (isThinking || isSending) && !hasPendingRequests
    }

    private var statusColor: Color {
        if hasPendingRequests { return .orange }
        if isThinking { return .blue }
        if isSending { return .yellow }
        if !isConnected { return .gray }
        return .green
    }

    private var statusText: String {
        if hasPendingRequests { return "permission required" }
        if isThinking { return vibingWord.lowercased() + "…" }
        if isSending { return "sending…" }
        if !isConnected { return "connecting…" }
        return "online"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .scaleEffect(shouldPulse ? (isPulsing ? 1.4 : 1.0) : 1.0)
                .animation(
                    shouldPulse
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

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

// MARK: - Slash Command Popup

struct SlashCommandPopup: View {
    let commands: [SlashCommand]
    let selectedIndex: Int
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let visible = Array(commands.prefix(12))
                    ForEach(Array(visible.enumerated()), id: \.element.name) { idx, cmd in
                        Button { onSelect(cmd) } label: {
                            HStack(spacing: 8) {
                                Text("/\(cmd.name)")
                                    .font(.body.monospaced().weight(.semibold))
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
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(idx == selectedIndex ? Color.primary.opacity(0.06) : .clear)
                        }
                        .buttonStyle(.plain)
                        .id(cmd.name)

                        if idx < visible.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
    }
}

// MARK: - Attachment Preview Row

struct AttachmentPreviewRow: View {
    let attachments: [PendingAttachment]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            VStack(spacing: 3) {
                Group {
                    if let data = attachment.previewData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "doc")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .overlay {
                    if attachment.isUploading {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.ultraThinMaterial)
                            .frame(width: 48, height: 48)
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .overlay {
                    if attachment.error != nil {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.red.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Text(attachment.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 56)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.white, .gray)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }
}
