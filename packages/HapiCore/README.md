# HapiCore

Shared Swift library for iOS and macOS HAPI clients.

## Status

**Phase 1 (current)**: Test infrastructure. Canonical source of shared logic with unit tests.
Both app targets still use their local copies. Run `swift test` to verify logic.

**Phase 2 (planned)**: Full integration. Add `public` access control, integrate as SPM dependency
in both Xcode projects, delete duplicate files from app targets.

## Running Tests

```bash
cd packages/HapiCore
swift test
```

## Shared Files (12)

These files are identical (or should be) across iOS and macOS:

| File | Purpose |
|------|---------|
| Models/Models.swift | Data types, SyncEvent parsing, AnyCodable |
| Models/MessageStatus.swift | Message status enum |
| Networking/APIClient.swift | REST API client |
| Networking/SSEClient.swift | Server-Sent Events client |
| Networking/SyncCoordinator.swift | SSE event routing to store |
| Storage/LocalStore.swift | File-backed message/session cache |
| Storage/MessageMerger.swift | Message merge & dedup logic |
| Utilities/Keychain.swift | Secure credential storage |
| Utilities/TokenManager.swift | JWT token management |
| ViewModels/AppState.swift | Root auth state |
| ViewModels/ChatViewModel.swift | Chat logic & real-time updates |
| ViewModels/SessionsViewModel.swift | Sessions list management |

## Sync Workflow

When changing shared logic:
1. Edit the file in `packages/HapiCore/Sources/HapiCore/`
2. Run `swift test` to verify
3. Copy the changed file to both `ios/HapiClient/Sources/` and `macos/HapiClient/Sources/`

Use the sync script: `./packages/sync-to-apps.sh`
