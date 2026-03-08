import SwiftUI

// MARK: - Agent / Model definitions

enum AgentType: String, CaseIterable, Identifiable {
    case claude, codex, gemini, opencode
    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .opencode: "Opencode"
        }
    }

    var models: [(value: String, label: String)] {
        switch self {
        case .claude:
            [("auto", "Auto"), ("opus", "Opus"), ("sonnet", "Sonnet")]
        case .codex:
            [("auto", "Auto"), ("gpt-5.2-codex", "GPT-5.2 Codex"), ("gpt-5.2", "GPT-5.2"),
             ("gpt-5.1-codex-max", "GPT-5.1 Codex Max"), ("gpt-5.1-codex-mini", "GPT-5.1 Codex Mini")]
        case .gemini:
            [("auto", "Auto"), ("gemini-3-pro-preview", "Gemini 3 Pro Preview"),
             ("gemini-2.5-pro", "Gemini 2.5 Pro"), ("gemini-2.5-flash", "Gemini 2.5 Flash")]
        case .opencode:
            []
        }
    }
}

enum SessionType: String, CaseIterable, Identifiable {
    case simple, worktree
    var id: String { rawValue }
    var label: String {
        switch self {
        case .simple: "Simple"
        case .worktree: "Worktree"
        }
    }
}

// MARK: - View

struct CreateSessionView: View {
    let api: APIClient
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var machines: [Machine] = []
    @State private var selectedMachineId: String = ""
    @State private var directory = ""
    @State private var sessionType: SessionType = .simple
    @State private var worktreeName = ""
    @State private var agent: AgentType = .claude
    @State private var model = "auto"
    @State private var yolo = false

    @State private var isLoadingMachines = true
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Machine") {
                    if isLoadingMachines {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading machines…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.caption)
                            Button("Retry") {
                                Task { await loadMachines() }
                            }
                        }
                    } else if machines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No machines available")
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task { await loadMachines() }
                            }
                        }
                    } else {
                        Picker("Machine", selection: $selectedMachineId) {
                            ForEach(machines) { machine in
                                Text(machine.displayLabel).tag(machine.id)
                            }
                        }
                    }
                }

                Section("Directory") {
                    TextField("/Users/username/project", text: $directory)
                    Text("Use absolute path on the remote machine")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Session Type") {
                    Picker("Type", selection: $sessionType) {
                        ForEach(SessionType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if sessionType == .worktree {
                        TextField("Worktree name (optional)", text: $worktreeName)
                    }
                }

                Section("Agent") {
                    Picker("Agent", selection: $agent) {
                        ForEach(AgentType.allCases) { a in
                            Text(a.label).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if !agent.models.isEmpty {
                    Section("Model") {
                        Picker("Model", selection: $model) {
                            ForEach(agent.models, id: \.value) { m in
                                Text(m.label).tag(m.value)
                            }
                        }
                    }
                }

                Section {
                    Toggle("YOLO Mode", isOn: $yolo)
                } footer: {
                    Text("Skip permission prompts for tool calls")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                Spacer()

                Button("Create") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || selectedMachineId.isEmpty || directory.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .overlay {
            if isCreating {
                Color.black.opacity(0.1)
                ProgressView("Creating session…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onChange(of: agent) { _, _ in
            model = agent.models.first?.value ?? "auto"
        }
        .task { await loadMachines() }
    }

    // MARK: - Actions

    private func loadMachines() async {
        isLoadingMachines = true
        errorMessage = nil
        do {
            machines = try await api.fetchMachines()
            if let first = machines.first {
                selectedMachineId = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMachines = false
    }

    private func create() async {
        let dir = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        if dir.hasPrefix("~") {
            errorMessage = "Use an absolute path (e.g. /Users/username/project) — ~ is not expanded on the remote machine"
            return
        }

        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        var body = SpawnRequest(directory: dir)
        body.agent = agent.rawValue
        if !agent.models.isEmpty && model != "auto" {
            body.model = model
        }
        if yolo { body.yolo = true }
        if sessionType == .worktree {
            body.sessionType = "worktree"
            if !worktreeName.isEmpty {
                body.worktreeName = worktreeName
            }
        }

        do {
            let response = try await api.spawnSession(machineId: selectedMachineId, body: body)
            if response.type == "success", let sessionId = response.sessionId {
                dismiss()
                onCreated(sessionId)
            } else {
                errorMessage = response.message ?? "Failed to create session"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
