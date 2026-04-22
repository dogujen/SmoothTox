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
    private let l10n = AppLocalizer.shared
    private var eventTask: Task<Void, Never>?
    private var incomingCallRingtoneTimer: Timer?
    private var ringtoneSound: NSSound?

    var peers: [Peer] = []
    var selectedPeerID: UUID?
    var selectedGroupID: UUID?
    var connectionState: ConnectionState = .offline
    var messageStore: [UUID: [ChatMessage]] = [:]
    var draftMessage = ""
    var isUserNearBottom = true
    var activeTransferProgress: Double = 0
    var selfToxID = "-"
    var didCopyToxID = false
    var messageSearchText = ""
    var peerSearchText = ""
    var pendingFriendRequests: [FriendRequest] = []
    var pendingGroupInvites: [GroupInviteRequest] = []
    var pendingGroupHistorySyncRequests: [GroupHistorySyncRequest] = []
    var pendingFileRequests: [FileTransferRequest] = []
    var voiceCallStates: [UUID: VoiceCallState] = [:]
    var groupRooms: [GroupRoom] = []
    var groupMembersByGroupID: [UUID: [GroupMember]] = [:]
    var addFriendIDInput = ""
    var hostGroupNameInput = ""
    var joinGroupInviteInput = ""
    var isAddFriendSheetPresented = false
    var isHostGroupSheetPresented = false
    var isJoinGroupSheetPresented = false
    var isResetConfirmationPresented = false
    var isBusy = false
    var isProfileSheetPresented = false
    var selfDisplayName = AppLocalizer.shared.text("profile.defaultName")
    var selfAvatarPath: String?
    var peerAvatarPaths: [UUID: String] = [:]
    var profileDraftName = ""
    var profileDraftAvatarPath: String?

    init(toxClient: ToxCoreClient) {
        self.toxClient = toxClient
    }

    var selectedPeerName: String {
        if let selectedGroupID,
           let group = groupRooms.first(where: { $0.id == selectedGroupID }) {
            return group.name
        }

        return peers.first(where: { $0.id == selectedPeerID })?.displayName ?? l10n.text("chat.defaultTitle")
    }

    var visibleMessages: [ChatMessage] {
        let conversationID: UUID?
        if let selectedGroupID {
            conversationID = selectedGroupID
        } else {
            conversationID = selectedPeerID
        }

        guard let conversationID else { return [] }
        let allMessages = messageStore[conversationID, default: []]
        let query = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allMessages }

        return allMessages.filter { message in
            message.text.localizedCaseInsensitiveContains(query)
                || message.attachmentURL?.lastPathComponent.localizedCaseInsensitiveContains(query) == true
        }
    }

    var visiblePeers: [Peer] {
        let query = peerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return peers }

        return peers.filter { peer in
            peer.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var visibleGroups: [GroupRoom] {
        let query = peerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groupRooms }

        return groupRooms.filter { room in
            room.name.localizedCaseInsensitiveContains(query)
                || room.chatID.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedGroupMembers: [GroupMember] {
        guard let selectedGroupID else { return [] }
        return groupMembersByGroupID[selectedGroupID, default: []]
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
        stopIncomingCallRingtone()

        Task {
            await toxClient.stop()
        }
    }

    func selectPeer(_ peerID: UUID) {
        selectedPeerID = peerID
        selectedGroupID = nil
    }

    func selectGroup(_ groupID: UUID) {
        selectedGroupID = groupID
        selectedPeerID = nil
    }

    func sendCurrentMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        draftMessage = ""

        if let selectedGroupID {
            let outgoing = ChatMessage(peerID: selectedGroupID, text: trimmed, isOutgoing: true)
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.12)) {
                messageStore[selectedGroupID, default: []].append(outgoing)
            }

            Task {
                _ = await toxClient.sendGroupMessage(trimmed, to: selectedGroupID)
            }
            return
        }

        guard let selectedPeerID else { return }

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

    var selectedPeerCallState: VoiceCallState {
        guard let selectedPeerID else { return .idle }
        return voiceCallStates[selectedPeerID] ?? .idle
    }

    var incomingCallPeerID: UUID? {
        voiceCallStates.first(where: { $0.value == .ringingIncoming })?.key
    }

    var incomingCallPeerName: String {
        guard let incomingCallPeerID,
              let peer = peers.first(where: { $0.id == incomingCallPeerID }) else {
            return l10n.text("call.unknownCaller")
        }
        return peer.displayName
    }

    var isIncomingCallPopupVisible: Bool {
        incomingCallPeerID != nil
    }

    func startCallWithSelectedPeer() {
        guard let selectedPeerID else { return }
        Task {
            _ = await toxClient.startVoiceCall(to: selectedPeerID)
        }
    }

    func acceptCallFromSelectedPeer() {
        guard let selectedPeerID else { return }
        Task {
            _ = await toxClient.acceptVoiceCall(from: selectedPeerID)
        }
    }

    func acceptIncomingCallFromPopup() {
        guard let incomingCallPeerID else { return }
        selectPeer(incomingCallPeerID)
        Task {
            _ = await toxClient.acceptVoiceCall(from: incomingCallPeerID)
        }
    }

    func declineIncomingCallFromPopup() {
        guard let incomingCallPeerID else { return }
        Task {
            await toxClient.endVoiceCall(with: incomingCallPeerID)
        }
    }

    func endCallWithSelectedPeer() {
        guard let selectedPeerID else { return }
        Task {
            await toxClient.endVoiceCall(with: selectedPeerID)
        }
    }

    func openHostGroupDialog() {
        hostGroupNameInput = ""
        isHostGroupSheetPresented = true
    }

    func openJoinGroupDialog() {
        joinGroupInviteInput = ""
        isJoinGroupSheetPresented = true
    }

    func submitHostGroup() {
        let name = hostGroupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await toxClient.hostGroup(named: name)
            if ok {
                isHostGroupSheetPresented = false
                hostGroupNameInput = ""
            }
        }
    }

    func submitJoinGroup() {
        let invite = joinGroupInviteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !invite.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await toxClient.joinGroup(invite: invite)
            if ok {
                isJoinGroupSheetPresented = false
                joinGroupInviteInput = ""
            }
        }
    }

    func leaveGroup(_ group: GroupRoom) {
        Task {
            await toxClient.leaveGroup(id: group.id)
        }
    }

    func acceptFriendRequest(_ request: FriendRequest) {
        pendingFriendRequests.removeAll(where: { $0.publicKeyHex == request.publicKeyHex })
        Task {
            await toxClient.acceptFriendRequest(publicKeyHex: request.publicKeyHex)
        }
    }

    func acceptGroupInvite(_ request: GroupInviteRequest) {
        pendingGroupInvites.removeAll(where: { $0.id == request.id })
        Task {
            _ = await toxClient.acceptGroupInvite(id: request.id)
        }
    }

    func rejectGroupInvite(_ request: GroupInviteRequest) {
        pendingGroupInvites.removeAll(where: { $0.id == request.id })
        Task {
            await toxClient.rejectGroupInvite(id: request.id)
        }
    }

    func acceptGroupHistorySyncRequest(_ request: GroupHistorySyncRequest) {
        pendingGroupHistorySyncRequests.removeAll(where: { $0.id == request.id })
        Task {
            await toxClient.resolveGroupHistorySyncRequest(id: request.id, allow: true)
        }
    }

    func rejectGroupHistorySyncRequest(_ request: GroupHistorySyncRequest) {
        pendingGroupHistorySyncRequests.removeAll(where: { $0.id == request.id })
        Task {
            await toxClient.resolveGroupHistorySyncRequest(id: request.id, allow: false)
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
                    text: l10n.format("message.file.sent", url.lastPathComponent),
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
            _ = await toxClient.sendFriendRequest(to: trimmed, message: l10n.text("friend.request.message"))
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

        case .voiceCallStateChanged(let peerID, let state):
            voiceCallStates[peerID] = state
            updateIncomingCallRingtoneState()

        case .selfDisplayNameUpdated(let displayName):
            selfDisplayName = displayName

        case .peerAvatarUpdated(let peerID, let avatarPath):
            peerAvatarPaths[peerID] = avatarPath
            peerAvatarStore.saveAvatarPath(avatarPath, for: peerID)

        case .peerAvatarCleared(let peerID):
            peerAvatarPaths.removeValue(forKey: peerID)
            peerAvatarStore.removeAvatarPath(for: peerID)

        case .groupRoomsUpdated(let rooms):
            groupRooms = rooms
            if let selectedGroupID,
               !rooms.contains(where: { $0.id == selectedGroupID }) {
                self.selectedGroupID = nil
            }
            groupMembersByGroupID = groupMembersByGroupID.filter { key, _ in
                rooms.contains(where: { $0.id == key })
            }

        case .groupInvitesUpdated(let invites):
            pendingGroupInvites = invites

        case .groupMembersUpdated(let groupID, let members):
            groupMembersByGroupID[groupID] = members

        case .groupHistorySyncAuthorizationRequested(let request):
            if !pendingGroupHistorySyncRequests.contains(where: { $0.id == request.id }) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    pendingGroupHistorySyncRequests.insert(request, at: 0)
                }
            }

        case .groupMessageReceived(let groupID, let senderName, let text):
            let incoming = ChatMessage(peerID: groupID, text: "\(senderName): \(text)", isOutgoing: false)
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                messageStore[groupID, default: []].append(incoming)
            }

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
            voiceCallStates = voiceCallStates.filter { entry in
                updatedPeers.contains(where: { $0.id == entry.key })
            }
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

    private func updateIncomingCallRingtoneState() {
        if incomingCallPeerID != nil {
            startIncomingCallRingtoneIfNeeded()
        } else {
            stopIncomingCallRingtone()
        }
    }

    private func startIncomingCallRingtoneIfNeeded() {
        if incomingCallRingtoneTimer != nil { return }

        let sound = NSSound(named: NSSound.Name("Submarine")) ?? NSSound(named: NSSound.Name("Glass"))
        ringtoneSound = sound
        sound?.stop()
        sound?.play()

        incomingCallRingtoneTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.incomingCallPeerID == nil {
                    self.stopIncomingCallRingtone()
                    return
                }
                self.ringtoneSound?.stop()
                self.ringtoneSound?.play()
            }
        }
    }

    private func stopIncomingCallRingtone() {
        incomingCallRingtoneTimer?.invalidate()
        incomingCallRingtoneTimer = nil
        ringtoneSound?.stop()
    }
}