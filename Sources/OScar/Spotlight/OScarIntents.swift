import AppIntents
import Foundation

// MARK: - Start Conversation Intent

/// Appears in Spotlight as "Start Oscar conversation" and via Siri.
struct StartConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Oscar Conversation"
    static var description = IntentDescription("Start a new conversation with the OScar agent.")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Query", description: "What do you want to ask?", default: "")
    var query: String

    func perform() async throws -> some IntentResult {
        // Post notification so OScarApp opens quick entry with the query pre-filled
        await MainActor.run {
            NotificationCenter.default.post(
                name: .oscOpenWithQuery,
                object: nil,
                userInfo: ["query": query]
            )
        }
        return .result()
    }
}

// MARK: - Continue Recent Session Intent

struct ContinueLastSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Last Oscar Session"
    static var description = IntentDescription("Resume your most recent OScar conversation.")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .oscContinueLastSession, object: nil)
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider (Spotlight phrase registration)

/// Registers phrase-based shortcuts so users can say/type
/// "Ask Oscar" or "Start Oscar conversation" in Spotlight.
struct OScarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartConversationIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Start \(.applicationName) conversation",
                "New \(.applicationName) session",
                "Open \(.applicationName)"
            ],
            shortTitle: "Ask Oscar",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: ContinueLastSessionIntent(),
            phrases: [
                "Continue \(.applicationName)",
                "Resume \(.applicationName)"
            ],
            shortTitle: "Continue Oscar",
            systemImageName: "arrow.counterclockwise"
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let oscOpenWithQuery = Notification.Name("com.oscarapp.openWithQuery")
    static let oscContinueLastSession = Notification.Name("com.oscarapp.continueLastSession")
    static let oscOpenSession = Notification.Name("com.oscarapp.openSession")
    static let oscOpenQuickEntry = Notification.Name("com.oscarapp.openQuickEntry")
}
