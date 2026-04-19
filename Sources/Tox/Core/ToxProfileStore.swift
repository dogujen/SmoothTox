import Foundation
import CryptoKit
import SQLite3
import Security

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class ToxProfileStore {
    private let service = "com.dogu.Tox"
    private let account = "tox_profile_key_v1"

    private let fm = FileManager.default
    private var cachedKey: Data?

    func loadProfileData() -> Data? {
        guard let encryptedBlob = readEncryptedBlobFromSQLite(),
              let key = loadOrCreateKey() else {
            return nil
        }

        do {
            let sealed = try AES.GCM.SealedBox(combined: encryptedBlob)
            return try AES.GCM.open(sealed, using: SymmetricKey(data: key))
        } catch {
            return nil
        }
    }

    func saveProfileData(_ data: Data) {
        guard let key = loadOrCreateKey() else { return }

        do {
            let sealed = try AES.GCM.seal(data, using: SymmetricKey(data: key))
            guard let combined = sealed.combined else { return }
            writeEncryptedBlobToSQLite(combined)
        } catch {
            return
        }
    }

    func resetAll() {
        deleteDatabaseFiles()
        deleteKeyFromKeychain()
        cachedKey = nil
    }

    private func databaseURL() -> URL? {
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let dir = appSupport.appendingPathComponent("Tox", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("profile.sqlite", isDirectory: false)
    }

    private func deleteDatabaseFiles() {
        guard let dbURL = databaseURL() else { return }
        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: dbURL.path + "-shm")

        try? fm.removeItem(at: dbURL)
        try? fm.removeItem(at: walURL)
        try? fm.removeItem(at: shmURL)
    }

    private func openDatabase() -> OpaquePointer? {
        guard let path = databaseURL()?.path else { return nil }

        var db: OpaquePointer?
        let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        guard result == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }

        _ = sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        _ = sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS tox_profile (id INTEGER PRIMARY KEY CHECK (id = 1), encrypted_blob BLOB NOT NULL, updated_at REAL NOT NULL);", nil, nil, nil)
        return db
    }

    private func writeEncryptedBlobToSQLite(_ blob: Data) {
        guard let db = openDatabase() else { return }
        defer { sqlite3_close(db) }

        let sql = "INSERT INTO tox_profile (id, encrypted_blob, updated_at) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET encrypted_blob=excluded.encrypted_blob, updated_at=excluded.updated_at;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return
        }
        defer { sqlite3_finalize(statement) }

        blob.withUnsafeBytes { buffer in
            _ = sqlite3_bind_blob(statement, 1, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
        }
        _ = sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        _ = sqlite3_step(statement)
    }

    private func readEncryptedBlobFromSQLite() -> Data? {
        guard let db = openDatabase() else { return nil }
        defer { sqlite3_close(db) }

        let sql = "SELECT encrypted_blob FROM tox_profile WHERE id = 1 LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard let bytes = sqlite3_column_blob(statement, 0) else {
            return nil
        }
        let length = Int(sqlite3_column_bytes(statement, 0))
        return Data(bytes: bytes, count: length)
    }

    private func loadOrCreateKey() -> Data? {
        if let cachedKey {
            return cachedKey
        }

        if let existing = readKeyFromKeychain() {
            cachedKey = existing
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }

        let keyData = Data(bytes)
        guard saveKeyToKeychain(keyData) else { return nil }
        cachedKey = keyData
        return keyData
    }

    private func readKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }

        return item as? Data
    }

    private func saveKeyToKeychain(_ key: Data) -> Bool {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }

        if addStatus == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attrs: [String: Any] = [
                kSecValueData as String: key
            ]
            return SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecSuccess
        }

        return false
    }

    private func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}