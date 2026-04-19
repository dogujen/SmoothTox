import Foundation

enum ToxEvent: Sendable {
    case connectionStateChanged(ConnectionState)
    case voiceCallStateChanged(peerID: UUID, state: VoiceCallState)
    case selfToxIDUpdated(String)
    case selfDisplayNameUpdated(String)
    case peerAvatarUpdated(peerID: UUID, avatarPath: String)
    case peerAvatarCleared(peerID: UUID)
    case groupRoomsUpdated([GroupRoom])
    case groupInvitesUpdated([GroupInviteRequest])
    case groupMembersUpdated(groupID: UUID, members: [GroupMember])
    case groupMessageReceived(groupID: UUID, senderName: String, text: String)
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
    func startVoiceCall(to peerID: UUID) async -> Bool
    func acceptVoiceCall(from peerID: UUID) async -> Bool
    func endVoiceCall(with peerID: UUID) async
    func hostGroup(named name: String) async -> Bool
    func joinGroup(invite: String) async -> Bool
    func leaveGroup(id: UUID) async
    func sendGroupMessage(_ text: String, to groupID: UUID) async -> Bool
    func acceptGroupInvite(id: UUID) async -> Bool
    func rejectGroupInvite(id: UUID) async
}