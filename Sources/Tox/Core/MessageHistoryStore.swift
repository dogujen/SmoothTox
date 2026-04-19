import Foundation
import SQLite3

final class MessageHistoryStore {
    private let fm = FileManager.default
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func loadAllMessages() -> [UUID: [ChatMessage]] {
        guard let db = openDatabase() else { return [:] }
        defer { sqlite3_close(db) }

        let sql = "SELECT message_id, peer_id, text, is_outgoing, timestamp, attachment_path FROM messages ORDER BY timestamp ASC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var grouped: [UUID: [ChatMessage]] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageIDCString = sqlite3_column_text(statement, 0),
                  let peerIDCString = sqlite3_column_text(statement, 1),
                  let textCString = sqlite3_column_text(statement, 2),
                  let messageID = UUID(uuidString: String(cString: messageIDCString)),
                  let peerID = UUID(uuidString: String(cString: peerIDCString)) else {
                continue
            }

            let text = String(cString: textCString)
            let isOutgoing = sqlite3_column_int(statement, 3) == 1
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

            var attachmentURL: URL?
            if let attachmentCString = sqlite3_column_text(statement, 5) {
                let path = String(cString: attachmentCString)
                if !path.isEmpty {
                    attachmentURL = URL(fileURLWithPath: path)
                }
            }

            let message = ChatMessage(
                id: messageID,
                peerID: peerID,
                text: text,
                isOutgoing: isOutgoing,
                timestamp: timestamp,
                attachmentURL: attachmentURL
            )
            grouped[peerID, default: []].append(message)
        }

        return grouped
    }

    func saveMessage(_ message: ChatMessage) {
        guard let db = openDatabase() else { return }
        defer { sqlite3_close(db) }

        let sql = "INSERT OR REPLACE INTO messages (message_id, peer_id, text, is_outgoing, timestamp, attachment_path) VALUES (?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return
        }
        defer { sqlite3_finalize(statement) }

        _ = sqlite3_bind_text(statement, 1, message.id.uuidString, -1, sqliteTransient)
        _ = sqlite3_bind_text(statement, 2, message.peerID.uuidString, -1, sqliteTransient)
        _ = sqlite3_bind_text(statement, 3, message.text, -1, sqliteTransient)
        _ = sqlite3_bind_int(statement, 4, message.isOutgoing ? 1 : 0)
        _ = sqlite3_bind_double(statement, 5, message.timestamp.timeIntervalSince1970)

        if let path = message.attachmentURL?.path {
            _ = sqlite3_bind_text(statement, 6, path, -1, sqliteTransient)
        } else {
            _ = sqlite3_bind_null(statement, 6)
        }

        _ = sqlite3_step(statement)
    }

    func clearAll() {
        guard let db = openDatabase() else { return }
        defer { sqlite3_close(db) }
        _ = sqlite3_exec(db, "DELETE FROM messages;", nil, nil, nil)
    }

    private func openDatabase() -> OpaquePointer? {
        guard let path = databaseURL()?.path else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db else {
            sqlite3_close(db)
            return nil
        }

        _ = sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        _ = sqlite3_exec(
            db,
            "CREATE TABLE IF NOT EXISTS messages (message_id TEXT PRIMARY KEY, peer_id TEXT NOT NULL, text TEXT NOT NULL, is_outgoing INTEGER NOT NULL, timestamp REAL NOT NULL, attachment_path TEXT);",
            nil,
            nil,
            nil
        )

        return db
    }

    private func databaseURL() -> URL? {
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let dir = appSupport.appendingPathComponent("Tox", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("messages.sqlite", isDirectory: false)
    }
}