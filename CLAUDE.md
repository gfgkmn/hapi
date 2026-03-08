# HAPI Project

Multi-platform chat client (iOS + macOS) that connects to a Hub server for remote Claude Code sessions.

## Architecture

### Data Flow: Message Delivery

```
User sends message
    → POST /sessions/:id/messages (APIClient)
    → Hub stores message, emits SSE "message-received"
    → CLI receives via socket, processes with Claude SDK
    → CLI sends response via socket "message" event
    → Hub stores response, emits SSE "message-received"
    → SSEClient receives, yields SyncEvent
    → SyncCoordinator.handleSSEEvent (on @MainActor)
        → LocalStore.ingestMessage (actor, updates cache)
        → events.send(.messagesChanged)
    → ChatViewModel Combine subscription
        → Task { @MainActor in reloadMessagesFromStore() }
        → messages = updated (triggers SwiftUI re-render)
```

### Key Components

| Component | Role |
|-----------|------|
| **SSEClient** | URLSession-based EventSource. Two connections: global (sessions) + per-session (messages) |
| **SyncCoordinator** | @MainActor. Owns SSE connections, routes events to LocalStore, publishes via Combine |
| **LocalStore** | Actor. File-backed cache for sessions and messages. Thread-safe. |
| **MessageMerger** | Pure functions. Merge/dedup logic: localId match → content-based fallback → id upsert |
| **ChatViewModel** | @MainActor. Owns message state, handles send/receive, slash commands, attachments |

### Known Gotchas

- **Task isolation in Combine sinks**: Always use `Task { @MainActor in ... }` when creating tasks inside Combine `.sink` closures. Plain `Task { }` inherits non-isolated context and `@Published` updates may not trigger SwiftUI re-renders.
- **SSE message routing**: `message-received` events are only sent to connections with matching `sessionId`. The global SSE (`all=true`) does NOT receive message events.
- **MessageMerger dedup**: Content-based dedup matches by role + exact text + 10s time window. Each server message consumes at most ONE optimistic message (prevents rapid-fire messages from being eaten).
- **Polling fallback**: Polls every 3s ONLY when SSE is disconnected. Do not rely on polling for real-time delivery.

## Project Structure

```
hapi/
├── cli/                    # Node.js CLI (hub connector + Claude SDK launcher)
├── hub/                    # Node.js server (message storage, SSE, socket.io)
├── ios/HapiClient/         # iOS app (SwiftUI)
├── macos/HapiClient/       # macOS app (SwiftUI)
│   └── project.yml         # XcodeGen config
└── packages/
    └── HapiCore/           # Shared Swift package (tests + canonical source)
        ├── Sources/        # 12 shared files (models, networking, storage, viewmodels)
        └── Tests/          # Unit tests (MessageMerger, SyncEvent parsing)
```

## Development Workflow

### Changing shared logic (Models, Networking, Storage, ViewModels)
1. Edit the file in `packages/HapiCore/Sources/HapiCore/`
2. Run `cd packages/HapiCore && swift test`
3. Run `bash packages/sync-to-apps.sh` to copy to both app targets
4. Build and test in Xcode

### Running tests
```bash
cd packages/HapiCore && swift test
```

### macOS build (XcodeGen)
```bash
cd macos && xcodegen generate && open HapiClient.xcodeproj
```

## Shared Files (12 files, identical across iOS + macOS)

Models: `Models.swift`, `MessageStatus.swift`
Networking: `APIClient.swift`, `SSEClient.swift`, `SyncCoordinator.swift`
Storage: `LocalStore.swift`, `MessageMerger.swift`
Utilities: `Keychain.swift`, `TokenManager.swift`
ViewModels: `AppState.swift`, `ChatViewModel.swift`, `SessionsViewModel.swift`

Platform-specific (NOT shared): All Views, `HapiClientApp.swift`
