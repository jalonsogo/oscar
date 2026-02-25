import Foundation
import CoreSpotlight
import AppKit

/// Indexes OScar sessions into Core Spotlight so they appear in Cmd+Space search.
class SpotlightIndexer {
    private static let domainIdentifier = "com.oscarapp.session"

    func indexSessions(_ sessions: [SessionSummary]) {
        let items: [CSSearchableItem] = sessions.map { makeItem(for: $0) }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("[Spotlight] indexing error: \(error)")
            }
        }
    }

    func removeSession(id: String) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [id]
        ) { _ in }
    }

    func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [Self.domainIdentifier]
        ) { _ in }
    }

    // MARK: - Private

    private func makeItem(for session: SessionSummary) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = session.title.isEmpty ? "Untitled session" : session.title
        attributes.contentDescription = "OScar · \(session.numMessages) messages"
        attributes.keywords = ["oscar", "agent", "cagent", "conversation", "ai"]
        if let dir = session.workingDir {
            attributes.path = dir
        }

        return CSSearchableItem(
            uniqueIdentifier: session.id,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
    }
}

// MARK: - NSUserActivity continuation (called by OScarApp)

extension SpotlightIndexer {
    /// Returns the session ID from a Spotlight-originated NSUserActivity, if any.
    static func sessionID(from activity: NSUserActivity) -> String? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }
        return id
    }
}
