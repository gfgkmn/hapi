# HAPI (Fork)

A fork of [tiann/hapi](https://github.com/tiann/hapi) — run official Claude Code / Codex / Gemini / OpenCode sessions locally and control them remotely.

> Great thanks to the original [HAPI](https://github.com/tiann/hapi) project and its upstream [Happy](https://github.com/slopus/happy) for the excellent architecture and foundation.

## What's different in this fork

### Native iOS & macOS Clients

Built native SwiftUI apps as alternatives to the Web / PWA client:

- **Shared core** (`packages/HapiCore/`) — 12 shared Swift files (models, networking, storage, viewmodels) with unit tests
- **Real-time sync** via SSE with optimistic message delivery and content-based dedup
- **Markdown rendering** with [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui), custom font support, and KaTeX math rendering
- **Collapsible tool blocks** — tool use (Bash, Read, etc.) collapsed to single-line summaries, expandable on tap
- **Output blocks** with line limits, word wrap toggle, and scroll mode
- **Permission management** — approve/deny tool use requests with scrollable detail view
- **Attachment support** — file and photo uploads
- **Slash commands** — `/status`, `/cost`, `/fast`, `/compact`, etc. with autocomplete popup

### CLI Enhancements

- `/fast` — toggle between Opus and Sonnet models
- `/memory` — display CLAUDE.md contents
- `/status`, `/cost`, `/plan` — session info commands handled locally
- Unified command routing with proper first-principle implementations

### UI/UX Polish

- Custom font integration (configurable body + code fonts)
- Inline LaTeX regex hardened against dollar-amount false positives in markdown tables
- iOS scroll position fix for variable-height content in LazyVStack

## Project Structure

```
hapi/
├── cli/                    # Node.js CLI (hub connector + Claude SDK launcher)
├── hub/                    # Node.js server (message storage, SSE, socket.io)
├── web/                    # React web client (original)
├── ios/HapiClient/         # iOS app (SwiftUI) — new
├── macos/HapiClient/       # macOS app (SwiftUI) — new
└── packages/
    └── HapiCore/           # Shared Swift package — new
```

## Getting Started

See the [original project](https://github.com/tiann/hapi) for Hub and CLI setup.

```bash
npx @twsxtd/hapi hub --relay     # start hub with E2E encrypted relay
npx @twsxtd/hapi                 # run claude code
```

### Native clients

```bash
# Run shared Swift tests
cd packages/HapiCore && swift test

# macOS (requires XcodeGen)
cd macos && xcodegen generate && open HapiClient.xcodeproj

# iOS
open ios/HapiClient.xcodeproj
```

## Build from source

```bash
bun install
bun run build:single-exe
```

## Credits

- [HAPI](https://github.com/tiann/hapi) by tiann — the upstream project this fork is based on
- [Happy](https://github.com/slopus/happy) — the original project that HAPI is derived from
- HAPI means "哈皮", a Chinese transliteration of Happy
