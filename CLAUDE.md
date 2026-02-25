# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What OScar Is

OScar (**O**perating **S**ystem for **C**ognitive **A**gent **R**untime) is a native macOS menu bar app that wraps [docker/cagent](https://github.com/docker/cagent). It provides:

- A persistent menu bar icon (no Dock entry) with session list popover
- Spotlight integration: sessions appear in Cmd+Space search; "Ask Oscar" phrase via App Intents
- A global quick-entry window to start or continue conversations
- Real-time streaming chat UI backed by cagent's SSE API

## Commands

```bash
# Open in Xcode (recommended — handles bundle, signing, Info.plist)
make xcode

# Build release binary
make build

# Build .app bundle for direct launch
make bundle

# Install to /Applications
make install

# Create default ~/.config/oscar/agent.yaml
make init-config

# Clean build artifacts
make clean
```

> **Important:** For Spotlight and App Intents to work, OScar must run as a proper `.app` bundle (use `make bundle` or Xcode). Running the bare binary via `swift run` suppresses Spotlight registration.

## Architecture

```
OScarApp.swift          @main entry; defines all SwiftUI Scenes
│
├── MenuBarExtra        MenuBarView popover (320 × ~480 pt window-style)
├── WindowGroup         ConversationView windows, keyed by "sessionId|initialQuery"
├── Window "quick-entry" QuickEntryView floating panel
└── Settings            SettingsView

Store/AppState.swift    @MainActor ObservableObject; single source of truth
├── CagentClient        URLSession-based REST + SSE client (actor)
├── CagentProcess       Manages `cagent serve api` subprocess lifecycle
└── SpotlightIndexer    CSSearchableItem indexing of sessions
```

### Key Data Flow

1. `OScarApp.init` → `AppState.start()` → tries existing server, else launches `CagentProcess`
2. Session list: `GET /api/sessions` → `AppState.sessions` → `SessionListView`
3. New conversation: `POST /api/sessions` → `openWindow(value: "id|query")` → `ConversationView`
4. Streaming: `POST /api/sessions/{id}/agent/{agentName}` SSE → `SSEParser` → `CagentEvent` enum → `ConversationView` state

### cagent API Surface Used

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/sessions` | List sessions |
| POST | `/api/sessions` | Create session |
| DELETE | `/api/sessions/{id}` | Delete session |
| PATCH | `/api/sessions/{id}/title` | Rename |
| POST | `/api/sessions/{id}/agent/{agent}` | Chat (SSE stream) |

All cagent SSE events are typed in `Models/Models.swift` and parsed in `API/SSEParser.swift`.

### Spotlight Integration

- **`SpotlightIndexer`**: Calls `CSSearchableIndex.default().indexSearchableItems` after every `loadSessions()`. Sessions appear in Spotlight with title + message count.
- **`OScarIntents`**: Defines `StartConversationIntent` and `ContinueLastSessionIntent` as `AppIntent` conformances, registered via `OScarShortcuts: AppShortcutsProvider`. Phrases like `"Ask Oscar about X"` appear in Spotlight (macOS 13+).
- **`NSUserActivity`** continuation in `AppDelegate` routes Spotlight taps back to the right conversation window.

### Session Window Routing

`WindowGroup(for: String.self)` receives a `"sessionId|initialQuery"` payload string. `ConversationView` splits on `|` to get the session ID and optional pre-filled query. This allows Spotlight, quick-entry, and session-list taps to all route through one scene.

## Prerequisites

- macOS 13.0+ (Ventura) — required for `MenuBarExtra`, `AppIntents`
- Xcode 15+ or Swift 5.9 toolchain
- [cagent](https://github.com/docker/cagent) installed (e.g. `brew install docker/tap/cagent`)
- An LLM provider API key set in your environment (e.g. `ANTHROPIC_API_KEY`)

## Configuration

OScar uses `UserDefaults` for settings (editable in Settings window):

| Key | Default | Purpose |
|-----|---------|---------|
| `cagentBinaryPath` | `/usr/local/bin/cagent` | Path to cagent binary |
| `agentConfigPath` | — | Path to agent YAML config |
| `serverPort` | `8080` | cagent API server port |
| `agentName` | `root` | Agent name within YAML |
| `workingDir` | `~` | Default working directory for sessions |

The default agent config is expected at `~/.config/oscar/agent.yaml`. A template is in `Examples/agent.yaml`.

## Adding New cagent Event Types

1. Add a case to `CagentEvent` enum in `Models/Models.swift`
2. Add a `Decodable` struct for the raw JSON if needed
3. Add a `case` in `SSEParser.decode(type:data:raw:)`
4. Handle the new case in `ConversationView.handleEvent(_:assistantMsgId:)`
