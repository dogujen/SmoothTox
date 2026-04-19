import Foundation

enum ToxEvent: Sendable {
    case connectionStateChanged(ConnectionState)
    case selfToxIDUpdated(String)
    case selfDisplayNameUpdated(String)
    case peerAvatarUpdated(peerID: UUID, avatarPath: String)
    case peerAvatarCleared(peerID: UUID)
    case friendRequestReceived(FriendRequest)
    case fileTransferRequestReceived(FileTransferRequest)
    case fileTransferUpdated(TransferProgress)
    case peerListUpdated([Peer])
    case messageReceived(ChatMessage)
}

protocol ToxCoreClient: Sendable {
    var events: AsyncStream<ToxEvent> { get }
    func start() async
    func stop() async
    func sendMessage(_ text: String, to peerID: UUID) async
    func acceptFriendRequest(publicKeyHex: String) async
    func sendFriendRequest(to toxID: String, message: String) async -> Bool
    func resetIdentityAndDatabase() async
    func exportProfileData() async -> Data?
    func sendFile(at url: URL, to peerID: UUID) async -> Bool
    func acceptFileTransfer(requestID: UUID) async
    func rejectFileTransfer(requestID: UUID) async
    func updateDisplayName(_ displayName: String) async -> Bool
    func updateAvatar(path: String?) async -> Bool
}