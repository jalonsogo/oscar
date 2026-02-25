import Foundation
import SQLite3

/// Reads conversation history directly from cagent's local SQLite database.
struct SessionStore {

    static var dbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cagent/session.db").path
    }

    /// Loads ordered user/assistant messages for a session from session_items.
    static func loadMessages(sessionId: String) -> [HistoryMessage] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT message_json FROM session_items
            WHERE session_id = ? AND item_type = 'message'
            ORDER BY position
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var result: [HistoryMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(stmt, 0) else { continue }
            let json = String(cString: cStr)
            guard let data = json.data(using: .utf8),
                  let msg = try? JSONDecoder().decode(MessageJSON.self, from: data),
                  !msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            result.append(HistoryMessage(role: msg.role, content: msg.content))
        }
        return result
    }

    // MARK: - Private

    private struct MessageJSON: Decodable {
        let role: String
        let content: String
    }
}

struct HistoryMessage {
    let role: String   // "user" | "assistant"
    let content: String
}
