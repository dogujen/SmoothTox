import Foundation

enum ConnectionState: Equatable {
    case offline
    case connecting
    case online
}

enum VoiceCallState: Equatable, Sendable {
    case idle
    case ringingIncoming
    case ringingOutgoing
    case inCall
}

struct Peer: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
}

struct SelfProfile: Sendable {
    let displayName: String
    let avatarPath: String?
}

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let peerID: UUID
    let text: String
    let isOutgoing: Bool
    let timestamp: Date
    let attachmentURL: URL?

    init(
        id: UUID = UUID(),
        peerID: UUID,
        text: String,
        isOutgoing: Bool,
        timestamp: Date = .now,
        attachmentURL: URL? = nil
    ) {
        self.id = id
        self.peerID = peerID
        self.text = text
        self.isOutgoing = isOutgoing
        self.timestamp = timestamp
        self.attachmentURL = attachmentURL
    }
}

struct TransferProgress: Equatable, Sendable {
    let transferID: UUID
    let peerID: UUID
    let progress: Double
}

struct FriendRequest: Identifiable, Hashable, Sendable {
    let publicKeyHex: String
    let message: String

    var id: String { publicKeyHex }
}

struct FileTransferRequest: Identifiable, Hashable, Sendable {
    let id: UUID
    let peerID: UUID
    let friendNumber: UInt32
    let fileNumber: UInt32
    let fileName: String
    let fileSize: UInt64

    init(
        id: UUID = UUID(),
        peerID: UUID,
        friendNumber: UInt32,
        fileNumber: UInt32,
        fileName: String,
        fileSize: UInt64
    ) {
        self.id = id
        self.peerID = peerID
        self.friendNumber = friendNumber
        self.fileNumber = fileNumber
        self.fileName = fileName
        self.fileSize = fileSize
    }
}

struct GroupRoom: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let chatID: String
    let isHost: Bool

    init(id: UUID = UUID(), name: String, chatID: String, isHost: Bool) {
        self.id = id
        self.name = name
        self.chatID = chatID
        self.isHost = isHost
    }
}

struct GroupInviteRequest: Identifiable, Hashable, Sendable {
    let id: UUID
    let inviterName: String
    let groupName: String

    init(id: UUID = UUID(), inviterName: String, groupName: String) {
        self.id = id
        self.inviterName = inviterName
        self.groupName = groupName
    }
}

struct GroupMember: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

struct GroupHistorySyncRequest: Identifiable, Hashable, Sendable {
    let id: UUID
    let groupID: UUID
    let groupName: String
    let requesterName: String
    let syncDeltaMinutes: UInt8

    init(
        id: UUID = UUID(),
        groupID: UUID,
        groupName: String,
        requesterName: String,
        syncDeltaMinutes: UInt8
    ) {
        self.id = id
        self.groupID = groupID
        self.groupName = groupName
        self.requesterName = requesterName
        self.syncDeltaMinutes = syncDeltaMinutes
    }
}