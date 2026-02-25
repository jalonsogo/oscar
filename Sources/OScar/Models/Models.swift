import Foundation

// MARK: - Session API Types

struct SessionSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let createdAt: String
    let numMessages: Int
    let inputTokens: Int64
    let outputTokens: Int64
    let workingDir: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case numMessages = "num_messages"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case workingDir = "working_dir"
    }

    // Custom decoder: numMessages/tokens may be absent in create-session responses
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        title        = try c.decode(String.self, forKey: .title)
        createdAt    = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        numMessages  = try c.decodeIfPresent(Int.self, forKey: .numMessages) ?? 0
        inputTokens  = try c.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0
        workingDir   = try c.decodeIfPresent(String.self, forKey: .workingDir)
    }
}

struct CreateSessionRequest: Encodable {
    var title: String
    var workingDir: String?
    var maxIterations: Int = 50
    var toolsApproved: Bool = false

    enum CodingKeys: String, CodingKey {
        case title
        case workingDir = "working_dir"
        case maxIterations = "max_iterations"
        case toolsApproved = "tools_approved"
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

// MARK: - Display Message (UI layer)

struct DisplayMessage: Identifiable {
    let id: UUID
    var role: MessageRole
    var content: String
    var toolName: String?
    var isError: Bool
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        toolName: String? = nil,
        isError: Bool = false,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolName = toolName
        self.isError = isError
        self.isStreaming = isStreaming
    }

    enum MessageRole {
        case user, assistant, tool, thinking, system
    }
}

// MARK: - SSE Event Types

enum CagentEvent {
    case userMessage(content: String, sessionId: String)
    case agentChoice(content: String, agentName: String?)
    case agentChoiceReasoning(content: String)
    case toolCall(id: String?, name: String, arguments: String)
    case toolResponse(name: String, response: String, isError: Bool)
    case tokenUsage(input: Int64, output: Int64, cost: Double)
    case sessionTitle(title: String, sessionId: String)
    case streamStarted
    case streamStopped
    case error(message: String)
    case warning(message: String)
    case elicitationRequest(message: String, elicitationId: String?)
    case maxIterationsReached
    case unknown(type: String)
}

// MARK: - Raw SSE Decodable Types

struct SSEBaseEvent: Decodable {
    let type: String
}

struct AgentChoiceEvent: Decodable {
    let type: String
    let content: String
    let agentName: String?

    enum CodingKeys: String, CodingKey {
        case type, content
        case agentName = "agent_name"
    }
}

struct UserMessageEvent: Decodable {
    let type: String
    let message: String
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case type, message
        case sessionId = "session_id"
    }
}

struct ToolCallEvent: Decodable {
    let type: String
    let toolCall: ToolCallData

    struct ToolCallData: Decodable {
        let id: String?
        let function: FunctionData

        struct FunctionData: Decodable {
            let name: String
            let arguments: String
        }

        enum CodingKeys: String, CodingKey {
            case id, function
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case toolCall = "tool_call"
    }
}

struct ToolCallResponseEvent: Decodable {
    let type: String
    let toolCall: ToolCallData
    let response: String
    let result: ResultData?

    struct ToolCallData: Decodable {
        let function: FunctionData
        struct FunctionData: Decodable { let name: String }
    }

    struct ResultData: Decodable {
        let isError: Bool?
        enum CodingKeys: String, CodingKey { case isError }
    }

    enum CodingKeys: String, CodingKey {
        case type, response, result
        case toolCall = "tool_call"
    }
}

struct TokenUsageEvent: Decodable {
    let type: String
    let usage: UsageData?

    struct UsageData: Decodable {
        let inputTokens: Int64?
        let outputTokens: Int64?
        let cost: Double?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cost
        }
    }

    enum CodingKeys: String, CodingKey { case type, usage }
}

struct SessionTitleEvent: Decodable {
    let type: String
    let title: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case type, title
        case sessionId = "session_id"
    }
}

struct ErrorEvent: Decodable {
    let type: String
    let message: String?
    let error: String?
}

struct ElicitationRequestEvent: Decodable {
    let type: String
    let message: String
    let elicitationId: String?

    enum CodingKeys: String, CodingKey {
        case type, message
        case elicitationId = "elicitation_id"
    }
}

// MARK: - Server Status

enum ServerStatus: Equatable {
    case stopped
    case launching
    case running
    case error(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .stopped: return "Stopped"
        case .launching: return "Starting..."
        case .running: return "Running"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
