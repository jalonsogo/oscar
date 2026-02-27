# OScar

**Operating System for Cognitive Agent Runtime** — a native macOS menu bar app that wraps [docker/cagent](https://github.com/docker/cagent), giving you a persistent AI agent that lives in your menu bar and can execute shell commands, read files, and answer questions about your machine.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

## What it does

- **Menu bar icon** — click to see your sessions list and start new conversations
- **Quick Entry** — floating prompt box with a searchable agent picker; type a question and press Enter
- **Streaming conversation window** — real-time SSE responses with tool calls, token usage, and session titles
- **Spotlight integration** — sessions appear in `⌘Space` search; say "Ask Oscar about X"
- **Session persistence** — shares `~/.cagent/session.db` with the `cagent` CLI
- **Multi-agent support** — switch between a folder of agent YAML configs directly from Quick Entry
- **Docker sandbox mode** — run cagent inside a Docker sandbox via `docker sandbox run`

## Prerequisites

| Requirement | Version |
|-------------|---------|
| macOS | 13.0 Ventura or later |
| Xcode / Swift toolchain | Xcode 15+ or Swift 5.9+ |
| [cagent](https://github.com/docker/cagent) | v1.23+ (`brew install docker/tap/cagent`) |
| LLM API key | e.g. `ANTHROPIC_API_KEY` in your environment |
| Docker Desktop *(optional)* | Required only for Docker sandbox mode |

## Quick start

```bash
# 1. Install cagent
brew install docker/tap/cagent

# 2. Create the default agent config
make init-config        # writes ~/.config/oscar/agent.yaml

# 3. Edit the config and add your API key to your shell environment
export ANTHROPIC_API_KEY=sk-ant-...

# 4. Build and install
make install            # builds release binary → /Applications/OScar.app

# 5. Launch
open /Applications/OScar.app
```

## Agent config

`make init-config` creates `~/.config/oscar/agent.yaml`:

```yaml
version: 1

agents:
  root:
    model: anthropic/claude-opus-4-6
    description: "OScar — your OS-level cognitive agent"
    instruction: |
      You are OScar, an intelligent assistant integrated into the macOS menu bar.
      You have access to shell commands and the filesystem to help the user
      accomplish real tasks on their machine.
    toolsets:
      - type: shell
      - type: filesystem
```

Change `model` to any provider/model supported by cagent (e.g. `openai/gpt-4o`, `google/gemini-2.0-flash`).

## Multi-agent support

Point OScar at a folder of `.yaml` agent configs in **Settings → Agents**. The Quick Entry window will show a searchable dropdown with three groups:

- **Default** — the single config set in Settings → General
- **Sandboxes** — Docker sandbox variants (e.g. `claude-box`, `codex-box`) built from the box-agent suffix
- **Agents** — all `.yaml` files discovered in your agents folder

Selecting a sandbox or custom agent from the dropdown routes that session through the chosen config.

## Docker sandbox mode

Enable **Settings → Docker → Sandbox server mode** to launch cagent inside a Docker sandbox (`docker sandbox run --publish 127.0.0.1:<port>:8080 cagent`). This isolates tool calls (shell, filesystem) inside a container.

- Requires Docker Desktop to be installed and running.
- Enable **--yolo** to skip Docker's confirmation prompts for destructive operations.

Example Docker toolset config:

```yaml
toolsets:
  - type: docker
  - type: mcp
    ref: docker:duckduckgo
  - type: mcp
    ref: docker:brave-search
```

## Build commands

```bash
make build          # compile release binary
make bundle         # build .app bundle under .build/OScar.app
make install        # bundle + copy to /Applications
make xcode          # open OScar.xcodeproj in Xcode
make init-config    # create default ~/.config/oscar/agent.yaml
make clean          # remove .build/
```

> **Spotlight & App Intents** require running as a proper `.app` bundle (`make install` or Xcode). The bare `swift run` binary skips Spotlight registration.

## Settings

Open Settings from the gear icon in the menu bar popover footer. All values are stored in `UserDefaults`.

### General

| Setting | Default | Description |
|---------|---------|-------------|
| Agent name | `agent` | Run mode passed to the cagent API (`/agent/{name}`) |
| Config file | `~/.config/oscar/agent.yaml` | Path to your default cagent YAML config |
| Sessions folder | — | Folder for session storage (optional override) |
| Working dir | `~` | Default working directory for new sessions |
| cagent binary | `/usr/local/bin/cagent` | Path to the cagent executable |
| Port | `8080` | Port for the cagent API server |

### Agents

| Setting | Default | Description |
|---------|---------|-------------|
| Agents folder | — | Folder of `.yaml` agent configs shown in Quick Entry |

### Docker

| Setting | Default | Description |
|---------|---------|-------------|
| Box-agent suffix | `-box` | Suffix appended to sandbox agent names (e.g. `claude-box`) |
| Sandbox server mode | off | Launch cagent via `docker sandbox run` |
| --yolo | off | Skip Docker confirmation prompts |

## Architecture

```
AppDelegate
├── AppState (@MainActor ObservableObject)
│   ├── CagentClient (actor) — REST + SSE via URLSession
│   ├── CagentProcess        — manages `cagent api` or `docker sandbox run` subprocess
│   └── SpotlightIndexer     — CSSearchableItem per session
├── MenuBarController        — NSStatusItem + NSPopover
└── WindowManager            — creates/tracks NSWindow instances
    ├── Conversation windows — one per session (keyed by session ID)
    └── Quick Entry window   — floating KeyableWindow, borderless
```

Sessions flow: `QuickEntryView` → `AppState.createSession()` → `WindowManager.open()` → `ConversationView` (SSE stream via `CagentClient.chat()`).

## License

MIT
