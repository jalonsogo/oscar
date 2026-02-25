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

OScar uses a **pure AppKit entry point** (NOT SwiftUI `@main`). SwiftUI `MenuBarExtra` and `WindowGroup` were abandoned because they silently fail on macOS 26 Tahoe and trigger deallocation races when `setActivationPolicy` is called.

```
main.swift              Pure AppKit entry: NSApplication + AppDelegate
AppDelegate.swift       applicationDidFinishLaunching; owns MenuBarController + WindowManager

MenuBar/
  MenuBarController.swift   NSStatusItem + NSPopover; hosts SwiftUI MenuBarView inside popover
  WindowManager.swift       Creates/tracks NSWindow instances for conversations + quick-entry

Store/AppState.swift    @MainActor ObservableObject; single source of truth
  CagentClient            URLSession-based REST + SSE client (actor)
  CagentProcess           Manages `cagent api` subprocess lifecycle
  SpotlightIndexer        CSSearchableItem indexing of sessions
```

### Key Data Flow

1. `AppDelegate` → `AppState.start()` → tries existing server, else launches `CagentProcess`
2. Session list: `GET /api/sessions` → `AppState.sessions` → `SessionListView`
3. New conversation: `POST /api/sessions` → `AppState.openWindowAction("id|query")` → `WindowManager.open()` → `ConversationView`
4. Streaming: `POST /api/sessions/{id}/agent/agent` SSE → `SSEParser` → `CagentEvent` enum → `ConversationView` state

### Session Window Routing

`WindowManager` holds a `[String: NSWindow]` dict keyed by session ID. `AppState.openWindowAction` is a closure set by `WindowManager.setup(state:)`. The payload `"sessionId|initialQuery"` is split by `ConversationView` to get the session ID and optional pre-filled query.

### cagent API Surface Used

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/sessions` | List sessions |
| POST | `/api/sessions` | Create session |
| DELETE | `/api/sessions/{id}` | Delete session |
| PATCH | `/api/sessions/{id}/title` | Rename |
| POST | `/api/sessions/{id}/agent/agent` | Chat (SSE stream) |

> **Note:** The path segment `agent` in the chat endpoint is the literal **run mode**, not the YAML config's agent name. Using any other value (e.g. `root`) returns `{"message":"failed to run session: agent not found: root"}`.

All cagent SSE events are typed in `Models/Models.swift` and parsed in `API/SSEParser.swift`.

### Spotlight Integration

- **`SpotlightIndexer`**: Calls `CSSearchableIndex.default().indexSearchableItems` after every `loadSessions()`. Sessions appear in Spotlight with title + message count.
- **`OScarIntents`**: Defines `StartConversationIntent` and `ContinueLastSessionIntent` as `AppIntent` conformances, registered via `OScarShortcuts: AppShortcutsProvider`. Phrases like `"Ask Oscar about X"` appear in Spotlight (macOS 13+).
- **`NSUserActivity`** continuation in `AppDelegate` routes Spotlight taps back to the right conversation window.

## Prerequisites

- macOS 13.0+ (Ventura) — required for `AppIntents`
- Xcode 15+ or Swift 5.9 toolchain
- [cagent](https://github.com/docker/cagent) v1.23+ installed (e.g. `brew install docker/tap/cagent`)
- An LLM provider API key set in your environment (e.g. `ANTHROPIC_API_KEY`)

## Configuration

OScar uses `UserDefaults` for settings (editable in Settings window):

| Key | Default | Purpose |
|-----|---------|---------|
| `cagentBinaryPath` | `/usr/local/bin/cagent` | Path to cagent binary |
| `agentConfigPath` | — | Path to agent YAML config |
| `serverPort` | `8080` | cagent API server port |
| `agentName` | `agent` | Run mode passed to `/agent/{mode}` endpoint |
| `workingDir` | `~` | Default working directory for sessions |

The default agent config is expected at `~/.config/oscar/agent.yaml`. A template is in `Examples/agent.yaml`.

## Known Pitfalls and Hard-Won Fixes

### 1. `NSWindow.isReleasedWhenClosed = false` is mandatory for ARC-owned windows

**Symptom:** `EXC_BAD_ACCESS` / `SIGSEGV KERN_INVALID_ADDRESS` in `objc_release` inside `AutoreleasePoolPage::releaseUntil` — always on the main thread, always after a window operation. Crash appears in `[NSApplication run]`'s autorelease drain, not at the line that caused it.

**Cause:** `NSWindow.isReleasedWhenClosed` defaults to `true`. This causes AppKit to call `[self release]` inside `close()`. When Swift ARC also holds a strong reference (e.g. in `conversationWindows: [String: NSWindow]` or `quickEntryWindow: NSWindow?`), there are now two releases for one allocation — a double-free. AppKit's autorelease pool (which still holds internal references from notification posting inside `close()`) then accesses freed/unmapped memory when it drains at the end of the event loop iteration.

**Fix:** Always set `window.isReleasedWhenClosed = false` on every window managed by ARC:
```swift
// In makeWindow() for conversation windows:
window.isReleasedWhenClosed = false

// In openQuickEntry() for the floating panel:
window.isReleasedWhenClosed = false
```

### 2. Never close a window from inside its own view's method

**Symptom:** Same `EXC_BAD_ACCESS` as above, but triggered by an `onClose` callback.

**Cause:** If `QuickEntryView.create()` calls a closure that closes the QuickEntry window, it frees the window's SwiftUI hosting hierarchy while `create()` is still executing as a method of a view owned by that hierarchy. The method's implicit `self` reference becomes a dangling pointer mid-execution.

**Fix:** Defer window closure to the **next main-actor turn** after the view method returns:
```swift
// In WindowManager.open():
openConversation(sessionId: sessionId, initialQuery: query)
Task { @MainActor [weak self] in self?.closeQuickEntry() }
// ↑ Runs AFTER create() has fully returned and its autorelease pool has drained
```
Do not pass `onClose` callbacks into SwiftUI views that close their own hosting window.

### 3. Hold a strong reference to every window you create

**Symptom:** QuickEntry window appears and immediately disappears, or is freed before the user interacts with it.

**Cause:** After `openQuickEntry()` returns, if you don't store the window somewhere, the only strong reference is AppKit's internal window list. When `close()` removes it from that list, ARC immediately frees it.

**Fix:** `WindowManager` holds `private var quickEntryWindow: NSWindow?` and assigns it before the method returns. Nil it only in `closeQuickEntry()`.

### 4. cagent API run mode is literally `"agent"`, not your YAML agent name

**Symptom:** `{"message":"failed to run session: agent not found: root"}` — SSE stream returns an error event immediately with no AI response.

**Cause:** The chat endpoint is `POST /api/sessions/{id}/agent/{mode}` where `{mode}` is `agent` — a fixed run mode string, not the name of the agent defined in your YAML (e.g. `root`).

**Fix:** Default `agentName` to `"agent"` (not `"root"`). If a user has a stale `UserDefaults` value, they can reset it:
```bash
defaults delete com.oscarapp.oscar agentName
```

### 5. Use `URLSession.shared` for SSE on macOS 26 Tahoe

**Symptom:** `EXC_BREAKPOINT` / `SIGTRAP` deep in `nw_connection_create_with_id` → `NWIOConnection::open()` → `_os_activity_stream_reflect` — happens the first time an SSE stream is initiated.

**Cause:** macOS 26 beta bug in the Network framework's XPC activity logging path, triggered when creating a brand-new `URLSession(configuration: .default)` inside a Task for each SSE request.

**Fix:** Use `URLSession.shared.bytes(for: request)` — the shared session reuses existing TCP connections (one was already established for health check polling), skipping `nw_connection_create`.

### 6. Use pure AppKit entry point, not SwiftUI `@main` + `MenuBarExtra`

**Symptom:** SwiftUI `MenuBarExtra` silently does nothing on macOS 26. `setActivationPolicy(.accessory)` called during SwiftUI scene setup triggers deallocation races.

**Fix:** `main.swift` with pure AppKit (`NSApplication.shared.delegate = AppDelegate()`). SwiftUI is only used for view rendering inside `NSHostingController`, not for scene/lifecycle management.

### 7. `NSObject` is required for AppKit target-action (`#selector`)

`MenuBarController` must subclass `NSObject` for `@objc func` methods used with `#selector` in `NSStatusBarButton.action`.

### 8. Borderless windows need `KeyableWindow` to accept text input

`NSWindow` with `.borderless` style mask cannot become key by default, so text fields inside it won't receive keyboard events.

**Fix:**
```swift
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

### 9. cagent command changed in v1.23.x

The subprocess command is `cagent api <config.yaml> --listen 127.0.0.1:<port>` (not `cagent serve api`). Check `CagentProcess.swift` if the server fails to start.

## Adding New cagent Event Types

1. Add a case to `CagentEvent` enum in `Models/Models.swift`
2. Add a `Decodable` struct for the raw JSON if needed
3. Add a `case` in `SSEParser.decode(type:data:raw:)`
4. Handle the new case in `ConversationView.handleEvent(_:assistantMsgId:)`
