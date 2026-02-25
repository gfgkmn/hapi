# HAPI iOS Client

A native SwiftUI iOS application for controlling and monitoring HAPI AI coding agent sessions.

## Requirements

- Xcode 15+
- iOS 17+ deployment target
- A running HAPI hub (local or remote)
- A HAPI access token

## Architecture

```
ios/
├── HapiClient.xcodeproj/       ← Xcode project file
└── HapiClient/
    └── Sources/
        ├── HapiClientApp.swift         ← @main entry point
        ├── Models/
        │   └── Models.swift            ← Swift types mirroring shared/src/schemas.ts
        ├── Networking/
        │   ├── APIClient.swift         ← REST API client (URLSession)
        │   └── SSEClient.swift         ← Server-Sent Events client (AsyncStream)
        ├── Utilities/
        │   ├── Keychain.swift          ← Secure token storage
        │   └── TokenManager.swift      ← JWT expiry + refresh scheduling
        ├── ViewModels/
        │   ├── AppState.swift          ← Root auth state
        │   ├── SessionsViewModel.swift ← Sessions list + SSE
        │   └── ChatViewModel.swift     ← Per-session messages + SSE
        └── Views/
            ├── ContentView.swift       ← Auth gate (Login vs Sessions)
            ├── LoginView.swift         ← Access token + server URL entry
            ├── SessionsView.swift      ← Session list with swipe actions
            └── ChatView.swift          ← Chat messages + permission banners
```

## Getting Started

1. Open `HapiClient.xcodeproj` in Xcode 15+
2. Select an iPhone 17 simulator or physical device
3. Build & run (⌘R)
4. Enter your HAPI hub URL (e.g. `http://localhost:3000`) and access token
5. Your sessions will appear — tap one to start chatting

## API Surface Used

| Feature | Method |
|---|---|
| Auth | `POST /api/auth` |
| Sessions list | `GET /api/sessions` |
| Session detail | `GET /api/sessions/:id` |
| Messages (paginated) | `GET /api/sessions/:id/messages` |
| Send message | `POST /api/sessions/:id/messages` |
| Approve permission | `POST /api/sessions/:id/permissions/:id/approve` |
| Deny permission | `POST /api/sessions/:id/permissions/:id/deny` |
| Abort session | `POST /api/sessions/:id/abort` |
| Archive session | `POST /api/sessions/:id/archive` |
| Delete session | `DELETE /api/sessions/:id` |
| Rename session | `PATCH /api/sessions/:id` |
| Real-time events | `GET /api/events` (SSE) |

## MVP Feature Set

- [x] Login with access token (stored in Keychain)
- [x] Sessions list with active/inactive indicator
- [x] Pull-to-refresh sessions
- [x] Swipe to archive / delete / stop sessions
- [x] Chat view with paginated message history
- [x] Load older messages on demand
- [x] Send messages
- [x] Real-time updates via SSE (new messages, session state changes)
- [x] Permission approval/denial inline banners
- [x] "Thinking" indicator when agent is active
- [x] Tool use display in message thread
- [x] Auto-login on relaunch (credentials persisted in Keychain)
- [x] JWT refresh 60s before expiry

## Phase 2 (not yet implemented)

- [ ] Machine list + spawn new sessions
- [ ] File browser
- [ ] Git diff viewer
- [ ] APNs push notifications

## Phase 3 (advanced)

- [ ] Terminal emulator via Socket.IO
- [ ] Voice assistant via ElevenLabs WebRTC
