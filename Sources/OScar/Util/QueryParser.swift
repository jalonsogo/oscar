import Foundation

/// Result of parsing an optional agent prefix from user input.
struct ParsedQuery {
    /// The cleaned query text, with the prefix stripped.
    let query: String
    /// The agent name extracted from the prefix (nil = use the global default).
    let agentName: String?
    /// Whether the user requested sandbox (box) mode.
    let sandbox: Bool

    /// The effective agent name to pass to the cagent API.
    /// `box/claude/…` → `claude-box`; `claude/…` → `claude`; no prefix → nil.
    /// When nil the caller falls back to `AppState.agentName`.
    var effectiveAgentName: String? {
        guard let name = agentName else { return nil }
        return sandbox ? "\(name)-box" : name
    }
}

/// Parses an optional agent prefix from raw user input.
///
/// Supported formats:
///
///   box/<agentName>/<query>   — sandbox mode with a named agent
///   <agentName>/<query>       — named agent, default mode
///   <query>                   — no prefix; use the global agent setting
///
/// A prefix segment is only recognised when it contains no spaces.
/// Slashes inside the query itself are preserved.
///
/// Examples:
///   "claude/What is Docker?"      → agent: "claude",     sandbox: false
///   "box/claude/Write a script"   → agent: "claude-box", sandbox: true
///   "How do I list files?"        → agent: nil (global default)
func parseQueryPrefix(_ raw: String) -> ParsedQuery {
    let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // Split at most twice so that slashes inside the query are preserved.
    let parts = input.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        .map(String.init)

    guard parts.count >= 2 else {
        return ParsedQuery(query: input, agentName: nil, sandbox: false)
    }

    let first = parts[0]
    // Prefix segments must be single words (no spaces, non-empty).
    guard !first.isEmpty, !first.contains(" ") else {
        return ParsedQuery(query: input, agentName: nil, sandbox: false)
    }

    // box/<agentName>/<query> — requires all three segments.
    if first == "box" {
        guard parts.count == 3 else {
            return ParsedQuery(query: input, agentName: nil, sandbox: false)
        }
        let agent = parts[1]
        guard !agent.isEmpty, !agent.contains(" ") else {
            return ParsedQuery(query: input, agentName: nil, sandbox: false)
        }
        return ParsedQuery(query: parts[2], agentName: agent, sandbox: true)
    }

    // <agentName>/<query>
    let query = parts[1...].joined(separator: "/")
    return ParsedQuery(query: query, agentName: first, sandbox: false)
}
