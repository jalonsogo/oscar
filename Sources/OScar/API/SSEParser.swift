import Foundation

/// Parses Server-Sent Events from cagent's streaming API into typed CagentEvents.
enum SSEParser {
    static func parse(line: String) -> CagentEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        guard !json.isEmpty, json != "[DONE]" else { return nil }

        guard let data = json.data(using: .utf8),
              let base = try? JSONDecoder().decode(SSEBaseEvent.self, from: data)
        else { return nil }

        return decode(type: base.type, data: data, raw: json)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func decode(type: String, data: Data, raw: String) -> CagentEvent {
        let decoder = JSONDecoder()

        switch type {
        case "agent_choice":
            if let e = try? decoder.decode(AgentChoiceEvent.self, from: data) {
                return .agentChoice(content: e.content, agentName: e.agentName, model: e.model)
            }

        case "agent_choice_reasoning":
            if let e = try? decoder.decode(AgentChoiceEvent.self, from: data) {
                return .agentChoiceReasoning(content: e.content)
            }

        case "user_message":
            if let e = try? decoder.decode(UserMessageEvent.self, from: data) {
                return .userMessage(content: e.message, sessionId: e.sessionId)
            }

        case "tool_call":
            if let e = try? decoder.decode(ToolCallEvent.self, from: data) {
                return .toolCall(
                    id: e.toolCall.id,
                    name: e.toolCall.function.name,
                    arguments: e.toolCall.function.arguments
                )
            }

        case "tool_call_response":
            if let e = try? decoder.decode(ToolCallResponseEvent.self, from: data) {
                return .toolResponse(
                    name: e.toolCall.function.name,
                    response: e.response,
                    isError: e.result?.isError ?? false
                )
            }

        case "token_usage":
            if let e = try? decoder.decode(TokenUsageEvent.self, from: data) {
                return .tokenUsage(
                    input: e.usage?.inputTokens ?? 0,
                    output: e.usage?.outputTokens ?? 0,
                    cost: e.usage?.cost ?? 0,
                    model: e.usage?.model
                )
            }

        case "session_title":
            if let e = try? decoder.decode(SessionTitleEvent.self, from: data) {
                return .sessionTitle(
                    title: e.title ?? "",
                    sessionId: e.sessionId ?? ""
                )
            }

        case "stream_started":
            return .streamStarted

        case "stream_stopped":
            return .streamStopped

        case "error":
            if let e = try? decoder.decode(ErrorEvent.self, from: data) {
                return .error(message: e.message ?? e.error ?? "Unknown error")
            }

        case "warning":
            if let e = try? decoder.decode(ErrorEvent.self, from: data) {
                return .warning(message: e.message ?? e.error ?? "Unknown warning")
            }

        case "elicitation_request":
            if let e = try? decoder.decode(ElicitationRequestEvent.self, from: data) {
                return .elicitationRequest(message: e.message, elicitationId: e.elicitationId)
            }

        case "max_iterations_reached":
            return .maxIterationsReached

        default:
            break
        }

        return .unknown(type: type)
    }
}
