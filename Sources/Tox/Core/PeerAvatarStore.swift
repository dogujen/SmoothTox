import Foundation

final class PeerAvatarStore {
    private let defaults = UserDefaults.standard
    private let key = "smoothTox.peer.avatarPaths"

    func loadAvatarPath(for peerID: UUID) -> String? {
        loadAll()[peerID.uuidString.lowercased()]
    }

    func saveAvatarPath(_ path: String, for peerID: UUID) {
        var all = loadAll()
        all[peerID.uuidString.lowercased()] = path
        defaults.set(all, forKey: key)
    }

    func removeAvatarPath(for peerID: UUID) {
        var all = loadAll()
        all.removeValue(forKey: peerID.uuidString.lowercased())
        defaults.set(all, forKey: key)
    }

    private func loadAll() -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
