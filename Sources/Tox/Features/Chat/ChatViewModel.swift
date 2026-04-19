import Foundation
import Observation
import SwiftUI
import AppKit

@MainActor
@Observable
final class ChatViewModel {
    private let toxClient: ToxCoreClient
    private let historyStore = MessageHistoryStore()
    private let profileStore = UserProfileStore()
    private let peerAvatarStore = PeerAvatarStore()
    private var eventTask: Task<Void, Never>?

    var peers: [Peer] = []
    var selectedPeerID: UUID?
    var connectionState: ConnectionState = .offline
    var messageStore: [UUID: [ChatMessage]] = [:]
    var draftMessage = ""
    var isUserNearBottom = true
    var activeTransferProgress: Double = 0
    var selfToxID = "-"
    var didCopyToxID = false
    var messageSearchText = ""
    var pendingFriendRequests: [FriendRequest] = []
    var pendingFileRequests: [FileTransferRequest] = []
    var addFriendIDInput = ""
    var isAddFriendSheetPresented = false
    var isResetConfirmationPresented = false
    var isBusy = false
    var isProfileSheetPresented = false
    var selfDisplayName = "SmoothTox User"
    var selfAvatarPath: String?
    var peerAvatarPaths: [UUID: String] = [:]
    var profileDraftName = ""
    var profileDraftAvatarPath: String?

    init(toxClient: ToxCoreClient) {
        self.toxClient = toxClient
    }

    var selectedPeerName: String {
        peers.first(where: { $0.id == selectedPeerID })?.displayName ?? "Sohbet"
    }

    var visibleMessages: [ChatMessage] {
        guard let selectedPeerID else { return [] }
        let allMessages = messageStore[selectedPeerID, default: []]
        let query = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allMessages }

        return allMessages.filter { message in
            message.text.localizedCaseInsensitiveContains(query)
                || message.attachmentURL?.lastPathComponent.localizedCaseInsensitiveContains(query) == true
        }
    }

    func bootstrap() {
        guard eventTask == nil else { return }

        messageStore = historyStore.loadAllMessages()
        selfAvatarPath = profileStore.loadAvatarPath()

        eventTask = Task { [weak self] in
            guard let self else { return }
            await toxClient.start()
            for await event in toxClient.events {
                apply(event)
            }
        }
    }

    func shutdown() {
        eventTask?.cancel()
        eventTask = nil

        Task {
            await toxClient.stop()
        }
    }

    func selectPeer(_ peerID: UUID) {
        selectedPeerID = peerID
    }

    func sendCurrentMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let selectedPeerID else { return }

        draftMessage = ""

        let outgoing = ChatMessage(peerID: selectedPeerID, text: trimmed, isOutgoing: true)
        withAnimation(.spring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.12)) {
            messageStore[selectedPeerID, default: []].append(outgoing)
        }
        historyStore.saveMessage(outgoing)

        Task {
            await toxClient.sendMessage(trimmed, to: selectedPeerID)
        }
    }

    func avatarPath(for peerID: UUID) -> String? {
        peerAvatarPaths[peerID]
    }

    func copySelfToxID() {
        guard selfToxID != "-" else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selfToxID, forType: .string)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
            didCopyToxID = true
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                self?.didCopyToxID = false
            }
        }
    }

    func acceptFriendRequest(_ request: FriendRequest) {
        pendingFriendRequests.removeAll(where: { $0.publicKeyHex == request.publicKeyHex })
        Task {
            await toxClient.acceptFriendRequest(publicKeyHex: request.publicKeyHex)
        }
    }

    func sendFile(url: URL) {
        guard let selectedPeerID else { return }
        isBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await toxClient.sendFile(at: url, to: selectedPeerID)
            if ok {
                let fileMessage = ChatMessage(
                    peerID: selectedPeerID,
                    text: "Dosya gönderildi: \(url.lastPathComponent)",
                    isOutgoing: true,
                    attachmentURL: url
                )
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    messageStore[selectedPeerID, default: []].append(fileMessage)
                }
                historyStore.saveMessage(fileMessage)
            }
            isBusy = false
        }
    }

    func acceptFileRequest(_ request: FileTransferRequest) {
        pendingFileRequests.removeAll(where: { $0.id == request.id })
        Task {
            await toxClient.acceptFileTransfer(requestID: request.id)
        }
    }

    func rejectFileRequest(_ request: FileTransferRequest) {
        pendingFileRequests.removeAll(where: { $0.id == request.id })
        Task {
            await toxClient.rejectFileTransfer(requestID: request.id)
        }
    }

    func openAddFriendDialog() {
        addFriendIDInput = ""
        isAddFriendSheetPresented = true
    }

    func submitAddFriend() {
        let trimmed = addFriendIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await toxClient.sendFriendRequest(to: trimmed, message: "SmoothTox request")
            isBusy = false
            isAddFriendSheetPresented = false
            addFriendIDInput = ""
        }
    }

    func openProfileSettings() {
        profileDraftName = selfDisplayName
        profileDraftAvatarPath = selfAvatarPath
        isProfileSheetPresented = true
    }

    func setProfileDraftAvatar(url: URL) {
        profileDraftAvatarPath = url.path
    }

    func clearProfileDraftAvatar() {
        profileDraftAvatarPath = nil
    }

    func saveProfileSettings() {
        let name = profileDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            isProfileSheetPresented = false
            return
        }

        isBusy = true
        let avatarPath = profileDraftAvatarPath

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await toxClient.updateDisplayName(name)
            _ = await toxClient.updateAvatar(path: avatarPath)
            selfDisplayName = name
            selfAvatarPath = avatarPath
            profileStore.saveAvatarPath(avatarPath)
            isBusy = false
            isProfileSheetPresented = false
        }
    }

    func exportProfileData() async -> Data? {
        await toxClient.exportProfileData()
    }

    func resetIdentityAndDatabase() {
        isBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await toxClient.resetIdentityAndDatabase()
            isBusy = false
            isResetConfirmationPresented = false
            pendingFriendRequests.removeAll()
            messageStore.removeAll()
            historyStore.clearAll()
        }
    }

    private func apply(_ event: ToxEvent) {
        switch event {
        case .connectionStateChanged(let state):
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                connectionState = state
            }

        case .selfToxIDUpdated(let toxID):
            selfToxID = toxID

        case .selfDisplayNameUpdated(let displayName):
            selfDisplayName = displayName

        case .peerAvatarUpdated(let peerID, let avatarPath):
            peerAvatarPaths[peerID] = avatarPath
            peerAvatarStore.saveAvatarPath(avatarPath, for: peerID)

        case .peerAvatarCleared(let peerID):
            peerAvatarPaths.removeValue(forKey: peerID)
            peerAvatarStore.removeAvatarPath(for: peerID)

        case .friendRequestReceived(let request):
            if !pendingFriendRequests.contains(where: { $0.publicKeyHex == request.publicKeyHex }) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    pendingFriendRequests.insert(request, at: 0)
                }
            }

        case .fileTransferRequestReceived(let request):
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                pendingFileRequests.insert(request, at: 0)
            }

        case .peerListUpdated(let updatedPeers):
            peers = updatedPeers
            var nextAvatarPaths: [UUID: String] = [:]
            for peer in updatedPeers {
                if let path = peerAvatarStore.loadAvatarPath(for: peer.id) {
                    nextAvatarPaths[peer.id] = path
                }
            }
            peerAvatarPaths = nextAvatarPaths
            if selectedPeerID == nil {
                selectedPeerID = updatedPeers.first?.id
            }

        case .messageReceived(let message):
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                messageStore[message.peerID, default: []].append(message)
            }
            historyStore.saveMessage(message)

        case .fileTransferUpdated(let progress):
            activeTransferProgress = progress.progress
        }
    }
}