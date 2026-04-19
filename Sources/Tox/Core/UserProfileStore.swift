import Foundation

final class UserProfileStore {
    private let defaults = UserDefaults.standard
    private let avatarPathKey = "smoothTox.self.avatarPath"

    func loadAvatarPath() -> String? {
        defaults.string(forKey: avatarPathKey)
    }

    func saveAvatarPath(_ path: String?) {
        if let path {
            defaults.set(path, forKey: avatarPathKey)
        } else {
            defaults.removeObject(forKey: avatarPathKey)
        }
    }
}