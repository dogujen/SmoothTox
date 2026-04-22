import Foundation
import CryptoKit
import CToxWrapper

private struct IncomingFileContext {
    let request: FileTransferRequest
    let destinationURL: URL
    let handle: FileHandle
    var receivedBytes: UInt64
    let isAvatarTransfer: Bool
}

private struct OutgoingFileContext {
    let friendNumber: UInt32
    let fileNumber: UInt32
    let fileURL: URL
    let fileSize: UInt64
}

private struct PendingGroupInviteContext {
    let request: GroupInviteRequest
    let friendNumber: UInt32
    let inviteData: Data
}

private struct GroupSyncAuthorizationContext {
    let id: UUID
    let groupNumber: UInt32
    let requesterPeerID: UInt32
    let deltaMinutes: UInt8
}

private struct GroupHistoryEntry {
    let timestamp: Date
    let senderName: String
    let text: String
}

private let toxSelfConnectionCallback: toxw_self_connection_status_cb = { swiftUserData, connectionStatus in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    Task {
        await actor.onSelfConnectionStatus(connectionStatus)
    }
}

private let toxFriendConnectionCallback: toxw_friend_connection_status_cb = { swiftUserData, friendNumber, connectionStatus in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    Task {
        await actor.onFriendConnectionStatus(friendNumber: friendNumber, connectionStatus: connectionStatus)
    }
}

private let toxFriendNameCallback: toxw_friend_name_cb = { swiftUserData, friendNumber, nameBytes, length in
    guard let swiftUserData, let nameBytes else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    let data = Data(bytes: nameBytes, count: Int(length))
    let name = String(data: data, encoding: .utf8) ?? "Friend \(friendNumber)"
    Task {
        await actor.onFriendNameChanged(friendNumber: friendNumber, name: name)
    }
}

private let toxFriendMessageCallback: toxw_friend_message_cb = { swiftUserData, friendNumber, messageBytes, length in
    guard let swiftUserData, let messageBytes else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    let data = Data(bytes: messageBytes, count: Int(length))
    let text = String(data: data, encoding: .utf8) ?? ""
    Task {
        await actor.onFriendMessage(friendNumber: friendNumber, message: text)
    }
}

private let toxFriendRequestCallback: toxw_friend_request_cb = { swiftUserData, publicKeyBytes, messageBytes, length in
    guard let swiftUserData, let publicKeyBytes else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()

    let publicKeyData = Data(bytes: publicKeyBytes, count: 32)
    let messageData: Data
    if let messageBytes {
        messageData = Data(bytes: messageBytes, count: Int(length))
    } else {
        messageData = Data()
    }

    let message = String(data: messageData, encoding: .utf8) ?? ""
    Task {
        await actor.onFriendRequest(publicKeyHex: publicKeyData.hexUppercasedString(), message: message)
    }
}

private let toxFileRecvCallback: toxw_file_recv_cb = { swiftUserData, friendNumber, fileNumber, kind, fileSize, filenameBytes, filenameLength in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()

    let filenameData = filenameBytes.map { Data(bytes: $0, count: Int(filenameLength)) } ?? Data()
    let fileName = String(data: filenameData, encoding: .utf8) ?? "incoming-\(fileNumber)"

    Task {
        await actor.onFileTransferRequest(friendNumber: friendNumber, fileNumber: fileNumber, kind: kind, fileName: fileName, fileSize: fileSize)
    }
}

private let toxFileRecvChunkCallback: toxw_file_recv_chunk_cb = { swiftUserData, friendNumber, fileNumber, position, data, length in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    let chunk = (data != nil && length > 0) ? Data(bytes: data!, count: Int(length)) : Data()

    Task {
        await actor.onFileChunkReceived(friendNumber: friendNumber, fileNumber: fileNumber, position: position, chunk: chunk, isFinal: length == 0)
    }
}

private let toxFileChunkRequestCallback: toxw_file_chunk_request_cb = { swiftUserData, friendNumber, fileNumber, position, length in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    Task {
        await actor.onFileChunkRequest(friendNumber: friendNumber, fileNumber: fileNumber, position: position, length: length)
    }
}

private let toxFileRecvControlCallback: toxw_file_recv_control_cb = { swiftUserData, friendNumber, fileNumber, control in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    Task {
        await actor.onFileControl(friendNumber: friendNumber, fileNumber: fileNumber, control: control)
    }
}

private let toxAVCallCallback: toxw_av_call_cb = { swiftUserData, friendNumber, _, _ in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    Task {
        await actor.onIncomingCall(friendNumber: friendNumber)
    }
}

private let toxAVCallStateCallback: toxw_av_call_state_cb = { swiftUserData, friendNumber, state in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    Task {
        await actor.onCallStateChanged(friendNumber: friendNumber, state: state)
    }
}

private let toxAVAudioFrameCallback: toxw_av_audio_frame_cb = { swiftUserData, friendNumber, pcm, sampleCount, channels, samplingRate in
    guard let swiftUserData, let pcm, sampleCount > 0 else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    let total = Int(sampleCount) * Int(channels)
    let frame = Array(UnsafeBufferPointer(start: pcm, count: total))

    Task {
        await actor.onAudioFrameReceived(friendNumber: friendNumber, samples: frame, sampleCount: Int(sampleCount), channels: channels, sampleRate: samplingRate)
    }
}

private let toxGroupMessageCallback: toxw_group_message_cb = { swiftUserData, groupNumber, peerID, message, messageLength in
    guard let swiftUserData, let message, messageLength > 0 else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    let data = Data(bytes: message, count: Int(messageLength))
    let text = String(data: data, encoding: .utf8) ?? ""

    Task {
        await actor.onGroupMessage(groupNumber: groupNumber, peerID: peerID, text: text)
    }
}

private let toxGroupInviteCallback: toxw_group_invite_cb = { swiftUserData, friendNumber, inviteDataBytes, inviteDataLength, groupNameBytes, groupNameLength in
    guard let swiftUserData,
          let inviteDataBytes,
          inviteDataLength > 0 else { return }

    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    let inviteData = Data(bytes: inviteDataBytes, count: Int(inviteDataLength))
    let groupNameData = groupNameBytes.map { Data(bytes: $0, count: Int(groupNameLength)) } ?? Data()
    let groupName = String(data: groupNameData, encoding: .utf8) ?? ""

    Task {
        await actor.onGroupInvite(friendNumber: friendNumber, inviteData: inviteData, groupName: groupName)
    }
}

private let toxGroupPeerNameCallback: toxw_group_peer_name_cb = { swiftUserData, groupNumber, peerID, nameBytes, nameLength in
    guard let swiftUserData,
          let nameBytes,
          nameLength > 0 else { return }

    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    let nameData = Data(bytes: nameBytes, count: Int(nameLength))
    let name = String(data: nameData, encoding: .utf8) ?? ""

    Task {
        await actor.onGroupPeerNameChanged(groupNumber: groupNumber, peerID: peerID, name: name)
    }
}

private let toxGroupPeerJoinCallback: toxw_group_peer_join_cb = { swiftUserData, groupNumber, peerID in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()

    Task {
        await actor.onGroupPeerJoined(groupNumber: groupNumber, peerID: peerID)
    }
}

private let toxGroupPeerExitCallback: toxw_group_peer_exit_cb = { swiftUserData, groupNumber, peerID in
    guard let swiftUserData else { return }
    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()

    Task {
        await actor.onGroupPeerExited(groupNumber: groupNumber, peerID: peerID)
    }
}

private let toxGroupCustomPrivatePacketCallback: toxw_group_custom_private_packet_cb = { swiftUserData, groupNumber, peerID, data, dataLength in
    guard let swiftUserData,
          let data,
          dataLength > 0 else { return }

    let actor = Unmanaged<ToxCoreActor>.fromOpaque(swiftUserData).takeUnretainedValue()
    let packetData = Data(bytes: data, count: Int(dataLength))

    Task {
        await actor.onGroupCustomPrivatePacket(groupNumber: groupNumber, peerID: peerID, packetData: packetData)
    }
}

actor ToxCoreActor: ToxCoreClient {
    let events: AsyncStream<ToxEvent>

    private let eventContinuation: AsyncStream<ToxEvent>.Continuation
    private var loopTask: Task<Void, Never>?
    private var toxHandle: OpaquePointer?
    private let profileStore = ToxProfileStore()
    private var friendToPeer: [UInt32: Peer] = [:]
    private var peerToFriend: [UUID: UInt32] = [:]
    private var transferByPeer: [UUID: Double] = [:]
    private var pendingFileRequests: [UUID: FileTransferRequest] = [:]
    private var incomingFiles: [String: IncomingFileContext] = [:]
    private var outgoingFiles: [String: OutgoingFileContext] = [:]
    private var pendingOutboundMessages: [UInt32: [String]] = [:]
    private var voiceCallStates: [UUID: VoiceCallState] = [:]
    private var groupRooms: [GroupRoom] = []
    private var groupNumberToRoomID: [UInt32: UUID] = [:]
    private var pendingGroupInvites: [UUID: PendingGroupInviteContext] = [:]
    private var groupPeerNames: [UInt32: [UInt32: String]] = [:]
    private var pendingGroupSyncAuthorizations: [UUID: GroupSyncAuthorizationContext] = [:]
    private var groupHistoryByRoomID: [UUID: [GroupHistoryEntry]] = [:]
    private var seenGroupMessageKeys: [UUID: [String: Date]] = [:]
    private var hasConnectedOnce = false
    private var activeCallFriendNumber: UInt32?
    private let appConfig = BootstrapConfigLoader.loadFromBundle()
    private let l10n = AppLocalizer.shared
    private let userProfileStore = UserProfileStore()
    private var selfAvatarPath: String?
    private var selfDisplayNameCache: String = "SmoothTox"
    private let callAudioEngine = CallAudioEngine()
    private var isRunning = false
    private let avatarFilePrefix = "smoothtox-avatar-v1"
    private let avatarClearControlMessage = "[[SMOOTHTOX_AVATAR_CLEAR_V1]]"
    private let toxFileKindData: UInt32 = 0
    private let toxFileKindAvatar: UInt32 = 1
    private let toxavCallStateError: UInt32 = 1
    private let toxavCallStateFinished: UInt32 = 2
    private let persistedGroupChatIDsKey = "persisted_group_chat_ids_v1"
    private let groupLogsEnabled = true
    private let groupSyncMaxHistoryWindow: TimeInterval = 60 * 60 * 24 * 300
    private let groupSyncRequestPrefix = "ngch_request|v1|"
    private let groupSyncMessagePrefix = "ngch_syncmsg|v1|"
    private let groupSyncDefaultDeltaMinutes: UInt8 = 120

    init() {
        var continuation: AsyncStream<ToxEvent>.Continuation?
        self.events = AsyncStream<ToxEvent> { streamContinuation in
            continuation = streamContinuation
        }
        guard let continuation else {
            fatalError("AsyncStream continuation could not be created")
        }
        self.eventContinuation = continuation
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true

        eventContinuation.yield(.connectionStateChanged(.connecting))

        let savedata = profileStore.loadProfileData()
        let proxy = appConfig.network.effectiveProxy

        var createError: Int32 = 0
        let handle: OpaquePointer?

        if proxy.isEnabled, let proxyType = proxy.type {
            let proxyTypeRaw: UInt32 = (proxyType == .http) ? 2 : 1

            if let savedata, !savedata.isEmpty {
                handle = savedata.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return nil
                    }
                    return proxy.host.withCString { cHost in
                        toxw_create_with_proxy(baseAddress, rawBuffer.count, proxyTypeRaw, cHost, proxy.port, &createError)
                    }
                }
            } else {
                handle = proxy.host.withCString { cHost in
                    toxw_create_with_proxy(nil, 0, proxyTypeRaw, cHost, proxy.port, &createError)
                }
            }
        } else {
            if let savedata, !savedata.isEmpty {
                handle = savedata.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return nil
                    }
                    return toxw_create_from_savedata(baseAddress, rawBuffer.count, &createError)
                }
            } else {
                handle = toxw_create(&createError)
            }
        }

        guard let handle else {
            isRunning = false
            eventContinuation.yield(.connectionStateChanged(.offline))
            return
        }

        toxHandle = handle

        let userData = Unmanaged.passUnretained(self).toOpaque()
        toxw_set_callbacks(
            handle,
            userData,
            toxSelfConnectionCallback,
            toxFriendConnectionCallback,
            toxFriendNameCallback,
            toxFriendMessageCallback,
            toxFriendRequestCallback,
            toxFileRecvCallback,
            toxFileRecvChunkCallback,
            toxFileChunkRequestCallback,
            toxFileRecvControlCallback
        )
        toxw_set_av_callbacks(handle, toxAVCallCallback, toxAVCallStateCallback, toxAVAudioFrameCallback)
        toxw_set_group_callbacks(
            handle,
            toxGroupMessageCallback,
            toxGroupInviteCallback,
            toxGroupPeerNameCallback,
            toxGroupPeerJoinCallback,
            toxGroupPeerExitCallback,
            toxGroupCustomPrivatePacketCallback
        )

        bootstrapFromConfig()
        emitSelfAddressIfAvailable()
        emitSelfDisplayNameIfAvailable()
        selfAvatarPath = userProfileStore.loadAvatarPath()
        refreshPeerList()
        refreshGroupRooms()
        emit(.groupInvitesUpdated([]))

        Task {
            await autoRejoinPersistedGroupsIfNeeded()
        }

        loopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runIterationLoop()
        }
    }

    func stop() async {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil

        if let toxHandle {
            persistSavedata()
            toxw_destroy(toxHandle)
            self.toxHandle = nil
        }

        friendToPeer.removeAll()
        peerToFriend.removeAll()
        transferByPeer.removeAll()
        pendingFileRequests.removeAll()
        incomingFiles.removeAll()
        outgoingFiles.removeAll()
        pendingOutboundMessages.removeAll()
        voiceCallStates.removeAll()
        groupRooms.removeAll()
        groupNumberToRoomID.removeAll()
        pendingGroupInvites.removeAll()
        groupPeerNames.removeAll()
        pendingGroupSyncAuthorizations.removeAll()
        groupHistoryByRoomID.removeAll()
        seenGroupMessageKeys.removeAll()
        hasConnectedOnce = false
        activeCallFriendNumber = nil
        callAudioEngine.stopCapture()

        eventContinuation.yield(.peerListUpdated([]))
        eventContinuation.yield(.groupRoomsUpdated([]))
        eventContinuation.yield(.groupInvitesUpdated([]))
        eventContinuation.yield(.connectionStateChanged(.offline))
    }

    func sendMessage(_ text: String, to peerID: UUID) async {
        guard isRunning,
              let handle = toxHandle,
              let friendNumber = peerToFriend[peerID] else { return }

        if !attemptSendMessage(text, handle: handle, friendNumber: friendNumber) {
            pendingOutboundMessages[friendNumber, default: []].append(text)
        }
    }

    private func attemptSendMessage(_ text: String, handle: OpaquePointer, friendNumber: UInt32) -> Bool {
        let messageData = Data(text.utf8)
        if messageData.isEmpty { return true }

        var messageID: UInt32 = 0
        var sendError: Int32 = 0
        var didSend = false

        messageData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            didSend = toxw_send_message(
                handle,
                friendNumber,
                baseAddress,
                rawBuffer.count,
                &messageID,
                &sendError
            )
        }

        return didSend && sendError == 0
    }

    private func flushPendingMessages(for friendNumber: UInt32) {
        guard let handle = toxHandle,
              let queued = pendingOutboundMessages[friendNumber],
              !queued.isEmpty else { return }

        var stillPending: [String] = []
        for text in queued {
            if !attemptSendMessage(text, handle: handle, friendNumber: friendNumber) {
                stillPending.append(text)
            }
        }

        if stillPending.isEmpty {
            pendingOutboundMessages.removeValue(forKey: friendNumber)
        } else {
            pendingOutboundMessages[friendNumber] = stillPending
        }
    }

    func acceptFriendRequest(publicKeyHex: String) async {
        guard isRunning,
              let handle = toxHandle,
              let publicKeyData = Data(hexString: publicKeyHex),
              publicKeyData.count == 32 else {
            return
        }

        var friendNumber: UInt32 = 0
        var addError: Int32 = 0
        publicKeyData.withUnsafeBytes { rawBuffer in
            guard let key = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            _ = toxw_add_friend_norequest(handle, key, &friendNumber, &addError)
        }

        if addError == 0 {
            refreshPeerList()
            persistSavedata()
        }
    }

    func sendFriendRequest(to toxID: String, message: String) async -> Bool {
        guard isRunning,
              let handle = toxHandle,
              let addressData = Data(hexString: toxID),
              addressData.count == 38 else {
            return false
        }

        let requestMessageData = Data(message.utf8)
        if requestMessageData.isEmpty {
            return false
        }

        var friendNumber: UInt32 = 0
        var addError: Int32 = 0

        let addResult = addressData.withUnsafeBytes { addressBuffer in
            requestMessageData.withUnsafeBytes { messageBuffer in
                guard let addressBase = addressBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let messageBase = messageBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return false
                }

                return toxw_add_friend(
                    handle,
                    addressBase,
                    messageBase,
                    messageBuffer.count,
                    &friendNumber,
                    &addError
                )
            }
        }

        if addResult {
            refreshPeerList()
            persistSavedata()
        }

        return addResult && addError == 0
    }

    func sendFile(at url: URL, to peerID: UUID) async -> Bool {
        guard isRunning,
              let handle = toxHandle,
              let friendNumber = peerToFriend[peerID] else {
            return false
        }

        return sendFile(handle: handle, friendNumber: friendNumber, url: url, fileNameOverride: nil, fileKind: toxFileKindData)
    }

    func updateAvatar(path: String?) async -> Bool {
        let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedPath = (trimmedPath?.isEmpty == false) ? trimmedPath : nil
        selfAvatarPath = sanitizedPath

        guard isRunning, let handle = toxHandle else {
            return true
        }

        let friendNumbers = Array(friendToPeer.keys)

        if let sanitizedPath,
           FileManager.default.fileExists(atPath: sanitizedPath),
           let avatarURL = normalizedAvatarURL(for: sanitizedPath) {
            var sentAtLeastOne = false
            for friendNumber in friendNumbers {
                let fileName = avatarFileName(for: avatarURL)
                let sent = sendFile(handle: handle, friendNumber: friendNumber, url: avatarURL, fileNameOverride: fileName, fileKind: toxFileKindAvatar)
                sentAtLeastOne = sentAtLeastOne || sent
            }
            return sentAtLeastOne || friendNumbers.isEmpty
        }

        var didQueueOrSend = false
        for friendNumber in friendNumbers {
            if attemptSendMessage(avatarClearControlMessage, handle: handle, friendNumber: friendNumber) {
                didQueueOrSend = true
            } else {
                pendingOutboundMessages[friendNumber, default: []].append(avatarClearControlMessage)
                didQueueOrSend = true
            }
        }

        return didQueueOrSend || friendNumbers.isEmpty
    }

    func startVoiceCall(to peerID: UUID) async -> Bool {
        guard isRunning,
              let handle = toxHandle,
              let friendNumber = peerToFriend[peerID] else {
            return false
        }

        var error: Int32 = 0
        let ok = toxw_av_call(handle, friendNumber, 64, 0, &error)
        if ok, error == 0 {
            voiceCallStates[peerID] = .ringingOutgoing
            emit(.voiceCallStateChanged(peerID: peerID, state: .ringingOutgoing))
            return true
        }

        return false
    }

    func acceptVoiceCall(from peerID: UUID) async -> Bool {
        guard isRunning,
              let handle = toxHandle,
              let friendNumber = peerToFriend[peerID] else {
            return false
        }

        var error: Int32 = 0
        let ok = toxw_av_answer(handle, friendNumber, 64, 0, &error)
        if ok, error == 0 {
            voiceCallStates[peerID] = .inCall
            emit(.voiceCallStateChanged(peerID: peerID, state: .inCall))
            activeCallFriendNumber = friendNumber
            startAudioCaptureIfNeeded(for: friendNumber)
            return true
        }

        return false
    }

    func endVoiceCall(with peerID: UUID) async {
        guard isRunning,
              let handle = toxHandle,
              let friendNumber = peerToFriend[peerID] else {
            return
        }

        var error: Int32 = 0
        _ = toxw_av_call_control(handle, friendNumber, 2, &error)
        voiceCallStates[peerID] = .idle
        emit(.voiceCallStateChanged(peerID: peerID, state: .idle))
        if activeCallFriendNumber == friendNumber {
            activeCallFriendNumber = nil
            callAudioEngine.stopCapture()
        }
    }

    func hostGroup(named name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let handle = toxHandle,
              let selfName = currentSelfNameData() else { return false }

        let groupName = Data(trimmed.utf8)
        var groupNumber: UInt32 = 0
        var error: Int32 = 0

        let created = groupName.withUnsafeBytes { groupBuffer in
            selfName.withUnsafeBytes { selfBuffer in
                guard let groupBase = groupBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let selfBase = selfBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return false
                }

                return toxw_group_new_public(
                    handle,
                    groupBase,
                    groupBuffer.count,
                    selfBase,
                    selfBuffer.count,
                    &groupNumber,
                    &error
                )
            }
        }

        guard created, error == 0 else { return false }

        refreshGroupRooms()
        if let roomID = groupNumberToRoomID[groupNumber],
           let index = groupRooms.firstIndex(where: { $0.id == roomID }) {
            let room = groupRooms[index]
            groupRooms[index] = GroupRoom(id: room.id, name: trimmed, chatID: room.chatID, isHost: true)
            emit(.groupRoomsUpdated(groupRooms))
        }

        return true
    }

    func joinGroup(invite: String) async -> Bool {
        let trimmed = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let handle = toxHandle,
              let selfName = currentSelfNameData(),
              let chatID = Data(hexString: trimmed),
              chatID.count == Int(toxw_group_chat_id_size()) else { return false }

        let normalizedChatID = trimmed.uppercased()
        logGroup("join requested chatID=\(normalizedChatID.prefix(16))…")

        var groupNumber: UInt32 = 0
        var error: Int32 = 0

        let joined = chatID.withUnsafeBytes { chatBuffer in
            selfName.withUnsafeBytes { selfBuffer in
                guard let chatBase = chatBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let selfBase = selfBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return false
                }

                return toxw_group_join_by_chat_id(
                    handle,
                    chatBase,
                    chatBuffer.count,
                    selfBase,
                    selfBuffer.count,
                    &groupNumber,
                    &error
                )
            }
        }

        if !(joined && error == 0) {
            logGroup("join call returned failure error=\(error), checking existing rooms")
            refreshGroupRooms()
            if groupRooms.contains(where: { $0.chatID.uppercased() == normalizedChatID }) {
                logGroup("join treated as success because group already exists in local list")
                return true
            }
            logGroup("join failed chatID=\(normalizedChatID.prefix(16))…")
            return false
        }

        refreshGroupRooms()
        if let roomID = groupNumberToRoomID[groupNumber],
           let index = groupRooms.firstIndex(where: { $0.id == roomID }) {
            let room = groupRooms[index]
            if room.chatID.isEmpty {
                groupRooms[index] = GroupRoom(id: room.id, name: room.name, chatID: normalizedChatID, isHost: room.isHost)
                emit(.groupRoomsUpdated(groupRooms))
            }
        } else {
            let provisionalID = UUID()
            groupNumberToRoomID[groupNumber] = provisionalID
            let provisional = GroupRoom(
                id: provisionalID,
                name: "Group \(normalizedChatID.prefix(10))",
                chatID: normalizedChatID,
                isHost: false
            )
            groupRooms.append(provisional)
            emit(.groupRoomsUpdated(groupRooms))
            logGroup("join provisional room inserted groupNumber=\(groupNumber)")
        }

        appendPersistedGroupChatID(normalizedChatID)
        logGroup("join succeeded groupNumber=\(groupNumber) chatID=\(normalizedChatID.prefix(16))…")
        Task {
            await hydrateGroupPeers(groupNumber: groupNumber)
        }
        await refreshGroupRoomsWithRetry()
        return true
    }

    func leaveGroup(id: UUID) async {
        let removedChatID = groupRooms.first(where: { $0.id == id })?.chatID

        guard let groupNumber = groupNumberToRoomID.first(where: { $0.value == id })?.key,
              let handle = toxHandle else {
            return
        }

        var error: Int32 = 0
        _ = toxw_group_leave(handle, groupNumber, &error)

        if let removedChatID, !removedChatID.isEmpty {
            removePersistedGroupChatID(removedChatID)
        }

        groupRooms.removeAll(where: { $0.id == id })
        groupNumberToRoomID.removeValue(forKey: groupNumber)
        groupPeerNames.removeValue(forKey: groupNumber)
        emit(.groupRoomsUpdated(groupRooms))

        refreshGroupRooms()

        if let removedChatID, !removedChatID.isEmpty {
            logGroup("leave requested groupNumber=\(groupNumber) chatID=\(removedChatID.prefix(16))… error=\(error)")
        } else {
            logGroup("leave requested groupNumber=\(groupNumber) error=\(error)")
        }
    }

    func sendGroupMessage(_ text: String, to groupID: UUID) async -> Bool {
        guard let groupNumber = groupNumberToRoomID.first(where: { $0.value == groupID })?.key,
              let handle = toxHandle else {
            return false
        }

        let messageData = Data(text.utf8)
        if messageData.isEmpty { return false }

        var error: Int32 = 0
        let ok = messageData.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            return toxw_group_send_message(handle, groupNumber, base, buffer.count, &error)
        }

        if ok && error == 0 {
            _ = registerSeenGroupMessage(groupID: groupID, senderName: selfDisplayNameCache, text: text, timestamp: .now)
            appendGroupHistoryEntry(groupID: groupID, timestamp: .now, senderName: selfDisplayNameCache, text: text)
        }

        return ok && error == 0
    }

    func acceptGroupInvite(id: UUID) async -> Bool {
        guard let pending = pendingGroupInvites[id],
              let handle = toxHandle,
              let selfName = currentSelfNameData() else {
            return false
        }

        var groupNumber: UInt32 = 0
        var error: Int32 = 0

        let accepted = pending.inviteData.withUnsafeBytes { inviteBuffer in
            selfName.withUnsafeBytes { selfBuffer in
                guard let inviteBase = inviteBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let selfBase = selfBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return false
                }

                return toxw_group_invite_accept(
                    handle,
                    pending.friendNumber,
                    inviteBase,
                    inviteBuffer.count,
                    selfBase,
                    selfBuffer.count,
                    &groupNumber,
                    &error
                )
            }
        }

        guard accepted, error == 0 else {
            logGroup("invite accept failed inviterFriend=\(pending.friendNumber) error=\(error)")
            return false
        }

        logGroup("invite accepted inviterFriend=\(pending.friendNumber) groupNumber=\(groupNumber) name=\(pending.request.groupName)")

        pendingGroupInvites.removeValue(forKey: id)
        emitPendingGroupInvites()

        refreshGroupRooms()
        if let roomID = groupNumberToRoomID[groupNumber],
           let index = groupRooms.firstIndex(where: { $0.id == roomID }) {
            let room = groupRooms[index]
            groupRooms[index] = GroupRoom(id: room.id, name: pending.request.groupName, chatID: room.chatID, isHost: room.isHost)
            emit(.groupRoomsUpdated(groupRooms))
        } else {
            let provisionalID = UUID()
            groupNumberToRoomID[groupNumber] = provisionalID
            let provisional = GroupRoom(
                id: provisionalID,
                name: pending.request.groupName,
                chatID: "",
                isHost: false
            )
            groupRooms.append(provisional)
            emit(.groupRoomsUpdated(groupRooms))
        }

        await refreshGroupRoomsWithRetry()
        Task {
            await hydrateGroupPeers(groupNumber: groupNumber)
        }

        return true
    }

    func rejectGroupInvite(id: UUID) async {
        pendingGroupInvites.removeValue(forKey: id)
        emitPendingGroupInvites()
    }

    func resolveGroupHistorySyncRequest(id: UUID, allow: Bool) async {
        guard let pending = pendingGroupSyncAuthorizations.removeValue(forKey: id) else { return }
        guard allow else {
            logGroup("sync auth rejected groupNumber=\(pending.groupNumber) peerID=\(pending.requesterPeerID)")
            return
        }

        await sendGroupHistorySync(to: pending.requesterPeerID, groupNumber: pending.groupNumber, deltaMinutes: pending.deltaMinutes)
    }

    private func sendFile(handle: OpaquePointer, friendNumber: UInt32, url: URL, fileNameOverride: String?, fileKind: UInt32) -> Bool {
        let fileName = fileNameOverride ?? url.lastPathComponent
        let nameData = Data(fileName.utf8)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        if size == 0 || nameData.isEmpty { return false }

        var fileNumber: UInt32 = 0
        var errorCode: Int32 = 0

        let sent = nameData.withUnsafeBytes { nameBuffer in
            guard let nameBase = nameBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }

            return toxw_file_send(
                handle,
                friendNumber,
                fileKind,
                size,
                nil,
                nameBase,
                nameBuffer.count,
                &fileNumber,
                &errorCode
            )
        }

        guard sent, errorCode == 0 else { return false }

        let key = fileKey(friendNumber: friendNumber, fileNumber: fileNumber)
        outgoingFiles[key] = OutgoingFileContext(friendNumber: friendNumber, fileNumber: fileNumber, fileURL: url, fileSize: size)
        return true
    }

    func acceptFileTransfer(requestID: UUID) async {
        guard let request = pendingFileRequests.removeValue(forKey: requestID),
              let handle = toxHandle else { return }

        let destinationDir = downloadsDirectory()
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let destination = destinationDir.appendingPathComponent(request.fileName)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handleFile = try? FileHandle(forWritingTo: destination) else { return }

        let context = IncomingFileContext(
            request: request,
            destinationURL: destination,
            handle: handleFile,
            receivedBytes: 0,
            isAvatarTransfer: false
        )
        incomingFiles[fileKey(friendNumber: request.friendNumber, fileNumber: request.fileNumber)] = context

        var error: Int32 = 0
        _ = toxw_file_control(handle, request.friendNumber, request.fileNumber, 0, &error)
    }

    func rejectFileTransfer(requestID: UUID) async {
        guard let request = pendingFileRequests.removeValue(forKey: requestID),
              let handle = toxHandle else { return }

        var error: Int32 = 0
        _ = toxw_file_control(handle, request.friendNumber, request.fileNumber, 2, &error)
    }

    func updateDisplayName(_ displayName: String) async -> Bool {
        guard let handle = toxHandle else { return false }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let data = Data(trimmed.utf8)
        var error: Int32 = 0
        let ok = data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            return toxw_set_self_name(handle, base, buffer.count, &error)
        }

        if ok {
            selfDisplayNameCache = trimmed
            emit(.selfDisplayNameUpdated(trimmed))
            persistSavedata()
        }
        return ok && error == 0
    }

    func resetIdentityAndDatabase() async {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil

        if let toxHandle {
            toxw_destroy(toxHandle)
            self.toxHandle = nil
        }

        friendToPeer.removeAll()
        peerToFriend.removeAll()
        transferByPeer.removeAll()
        pendingFileRequests.removeAll()
        incomingFiles.removeAll()
        outgoingFiles.removeAll()
        pendingOutboundMessages.removeAll()
        voiceCallStates.removeAll()
        groupRooms.removeAll()
        groupNumberToRoomID.removeAll()
        pendingGroupInvites.removeAll()
        groupPeerNames.removeAll()
        activeCallFriendNumber = nil
        callAudioEngine.stopCapture()

        profileStore.resetAll()
        UserDefaults.standard.removeObject(forKey: persistedGroupChatIDsKey)
        eventContinuation.yield(.peerListUpdated([]))
        eventContinuation.yield(.groupRoomsUpdated([]))
        eventContinuation.yield(.groupInvitesUpdated([]))
        eventContinuation.yield(.selfToxIDUpdated("-"))
        eventContinuation.yield(.connectionStateChanged(.offline))

        await start()
    }

    func exportProfileData() async -> Data? {
        if let snapshot = snapshotSavedata() {
            return snapshot
        }

        return profileStore.loadProfileData()
    }

    private func runIterationLoop() async {
        while isRunning, !Task.isCancelled, let handle = toxHandle {
            toxw_iterate(handle)
            emitSelfAddressIfAvailable()

            let interval = max(10, Int(toxw_iteration_interval_ms(handle)))
            try? await Task.sleep(for: .milliseconds(interval))
        }
    }

    private func persistSavedata() {
        guard let data = snapshotSavedata() else { return }
        profileStore.saveProfileData(data)
    }

    private func snapshotSavedata() -> Data? {
        guard let handle = toxHandle else { return nil }

        let requiredSize = toxw_get_savedata_size(handle)
        guard requiredSize > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: requiredSize)
        var written: Int = 0

        let success = buffer.withUnsafeMutableBufferPointer { bytes in
            toxw_get_savedata(handle, bytes.baseAddress, bytes.count, &written)
        }

        guard success, written > 0, written <= buffer.count else { return nil }
        return Data(buffer[0..<written])
    }

    private func emitSelfAddressIfAvailable() {
        guard let handle = toxHandle else { return }

        var address = [UInt8](repeating: 0, count: 38)
        let success = address.withUnsafeMutableBufferPointer { ptr in
            toxw_get_self_address(handle, ptr.baseAddress)
        }

        guard success else { return }
        let toxID = Data(address).hexUppercasedString()
        emit(.selfToxIDUpdated(toxID))
    }

    private func emitSelfDisplayNameIfAvailable() {
        guard let handle = toxHandle else { return }

        var size: Int = 128
        var buffer = [UInt8](repeating: 0, count: size)
        let ok = buffer.withUnsafeMutableBufferPointer { ptr in
            toxw_get_self_name(handle, ptr.baseAddress, &size)
        }

        guard ok, size > 0, size <= buffer.count,
              let name = String(data: Data(buffer[0..<size]), encoding: .utf8),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

                selfDisplayNameCache = name
        emit(.selfDisplayNameUpdated(name))
    }

    private func bootstrapFromConfig() {
        guard let handle = toxHandle else { return }

        guard !appConfig.bootstrapNodes.isEmpty else {
            return
        }

        for node in appConfig.bootstrapNodes {
            guard let keyData = Data(hexString: node.publicKey), keyData.count == 32 else {
                continue
            }

            var bootstrapError: Int32 = 0
            keyData.withUnsafeBytes { rawBuffer in
                guard let key = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                node.host.withCString { cHost in
                    _ = toxw_bootstrap(handle, cHost, node.port, key, &bootstrapError)
                }
            }
        }
    }

    private func refreshPeerList() {
        guard let handle = toxHandle else { return }

        let friendCount = Int(toxw_get_friend_count(handle))
        guard friendCount > 0 else {
            friendToPeer.removeAll()
            peerToFriend.removeAll()
            eventContinuation.yield(.peerListUpdated([]))
            return
        }

        var friendNumbers = [UInt32](repeating: 0, count: friendCount)
        let receivedCount = friendNumbers.withUnsafeMutableBufferPointer { buffer in
            toxw_get_friend_list(handle, buffer.baseAddress, UInt32(buffer.count))
        }

        var nextFriendToPeer: [UInt32: Peer] = [:]
        var nextPeerToFriend: [UUID: UInt32] = [:]
        var orderedPeers: [Peer] = []

        for friendNumber in friendNumbers.prefix(Int(receivedCount)) {
            let existingPeer = friendToPeer[friendNumber]
            let peerID = existingPeer?.id ?? stablePeerID(friendNumber: friendNumber)
            let resolvedName = readFriendName(friendNumber: friendNumber)
                ?? existingPeer?.displayName
                ?? friendFallbackName(friendNumber: friendNumber)

            let peer = Peer(id: peerID, displayName: resolvedName)
            nextFriendToPeer[friendNumber] = peer
            nextPeerToFriend[peerID] = friendNumber
            orderedPeers.append(peer)
        }

        friendToPeer = nextFriendToPeer
        peerToFriend = nextPeerToFriend
        eventContinuation.yield(.peerListUpdated(orderedPeers))
    }

    private func stablePeerID(friendNumber: UInt32) -> UUID {
        guard let handle = toxHandle else { return UUID() }

        var key = [UInt8](repeating: 0, count: 32)
        let ok = key.withUnsafeMutableBufferPointer { ptr in
            toxw_get_friend_public_key(handle, friendNumber, ptr.baseAddress)
        }

        guard ok else { return UUID() }

        let digest = SHA256.hash(data: Data(key))
        var uuidBytes = Array(digest.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x40
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80

        let value = uuid_t(uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3], uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7], uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11], uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15])
        return UUID(uuid: value)
    }

    private func readFriendName(friendNumber: UInt32) -> String? {
        guard let handle = toxHandle else { return nil }

        var capacity: Int = 128
        var bytes = [UInt8](repeating: 0, count: capacity)

        let success = bytes.withUnsafeMutableBufferPointer { buffer in
            toxw_get_friend_name(handle, friendNumber, buffer.baseAddress, &capacity)
        }

        guard success, capacity > 0, capacity <= bytes.count else {
            return nil
        }

        let nameData = Data(bytes[0..<capacity])
        guard let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }

        return name
    }

    private func friendFallbackName(friendNumber: UInt32) -> String {
        guard let handle = toxHandle else { return "Peer" }
        var key = [UInt8](repeating: 0, count: 32)
        let ok = key.withUnsafeMutableBufferPointer { ptr in
            toxw_get_friend_public_key(handle, friendNumber, ptr.baseAddress)
        }

        if ok {
            let short = Data(key).hexUppercasedString().prefix(10)
            return "Peer \(short)"
        }

        return "Peer"
    }

    private func emitTransferPulse(for peerID: UUID) {
        let current = transferByPeer[peerID, default: 0]
        let next = current >= 0.98 ? 0.05 : min(current + 0.12, 1)
        transferByPeer[peerID] = next

        let progress = TransferProgress(
            transferID: UUID(),
            peerID: peerID,
            progress: next
        )
        eventContinuation.yield(.fileTransferUpdated(progress))
    }

    private func emit(_ event: ToxEvent) {
        eventContinuation.yield(event)
    }

    fileprivate func onSelfConnectionStatus(_ connectionStatus: UInt32) {
        let state: ConnectionState = connectionStatus == 0 ? .offline : .online
        hasConnectedOnce = connectionStatus > 0
        emit(.connectionStateChanged(state))
        emitSelfAddressIfAvailable()
        logGroup("self connection changed status=\(connectionStatus)")

        if connectionStatus > 0 {
            Task {
                await autoRejoinPersistedGroupsIfNeeded()
                await hydrateAllVisibleGroupPeers()
            }
        }
    }

    fileprivate func onFriendConnectionStatus(friendNumber: UInt32, connectionStatus: UInt32) {
        if connectionStatus > 0 {
            refreshPeerList()
            refreshGroupRooms()
            flushPendingMessages(for: friendNumber)
            sendSelfAvatarIfNeeded(to: friendNumber)
        }
        if let peer = friendToPeer[friendNumber] {
            emitTransferPulse(for: peer.id)
        }
    }

    fileprivate func onFriendNameChanged(friendNumber: UInt32, name: String) {
        guard let existing = friendToPeer[friendNumber] else {
            refreshPeerList()
            return
        }

        let updatedPeer = Peer(id: existing.id, displayName: name)
        friendToPeer[friendNumber] = updatedPeer

        let ordered = friendToPeer
            .sorted(by: { $0.key < $1.key })
            .map(\.value)
        emit(.peerListUpdated(ordered))
    }

    fileprivate func onFriendMessage(friendNumber: UInt32, message: String) {
        if message == avatarClearControlMessage {
            if let peer = friendToPeer[friendNumber] {
                emit(.peerAvatarCleared(peerID: peer.id))
            }
            return
        }

        guard let peer = friendToPeer[friendNumber] else {
            refreshPeerList()
            return
        }

        let incoming = ChatMessage(peerID: peer.id, text: message, isOutgoing: false)
        emit(.messageReceived(incoming))
        emitTransferPulse(for: peer.id)
    }

    fileprivate func onFriendRequest(publicKeyHex: String, message: String) {
        let request = FriendRequest(publicKeyHex: publicKeyHex, message: message)
        emit(.friendRequestReceived(request))
    }

    fileprivate func onGroupMessage(groupNumber: UInt32, peerID: UInt32, text: String) {
        guard let groupID = groupNumberToRoomID[groupNumber], !text.isEmpty else { return }
        let senderName = resolveGroupPeerName(groupNumber: groupNumber, peerID: peerID)
        setGroupPeerName(groupNumber: groupNumber, peerID: peerID, name: senderName)
        guard registerSeenGroupMessage(groupID: groupID, senderName: senderName, text: text, timestamp: .now) else {
            return
        }
        appendGroupHistoryEntry(groupID: groupID, timestamp: .now, senderName: senderName, text: text)
        emitGroupMembers(for: groupNumber)
        emit(.groupMessageReceived(groupID: groupID, senderName: senderName, text: text))
    }

    fileprivate func onGroupInvite(friendNumber: UInt32, inviteData: Data, groupName: String) {
        guard !inviteData.isEmpty else { return }

        let inviterName = friendToPeer[friendNumber]?.displayName ?? friendFallbackName(friendNumber: friendNumber)
        let normalizedGroupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalGroupName = normalizedGroupName.isEmpty ? l10n.text("group.invite.unknownName") : normalizedGroupName

        let request = GroupInviteRequest(inviterName: inviterName, groupName: finalGroupName)
        pendingGroupInvites[request.id] = PendingGroupInviteContext(
            request: request,
            friendNumber: friendNumber,
            inviteData: inviteData
        )
        logGroup("invite received from friend=\(friendNumber) groupName=\(finalGroupName) inviteBytes=\(inviteData.count)")
        emitPendingGroupInvites()
    }

    fileprivate func onGroupPeerNameChanged(groupNumber: UInt32, peerID: UInt32, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setGroupPeerName(groupNumber: groupNumber, peerID: peerID, name: trimmed)
        emitGroupMembers(for: groupNumber)
    }

    fileprivate func onGroupPeerJoined(groupNumber: UInt32, peerID: UInt32) {
        let existingName = groupPeerNames[groupNumber]?[peerID]
        if existingName == nil {
            setGroupPeerName(groupNumber: groupNumber, peerID: peerID, name: "Peer #\(peerID)")
            emitGroupMembers(for: groupNumber)
        }

        Task {
            let jitterSeconds = UInt64(Int.random(in: 2...8))
            try? await Task.sleep(for: .seconds(Int(jitterSeconds)))
            await sendHistorySyncRequestIfNeeded(groupNumber: groupNumber, peerID: peerID)
        }
    }

    fileprivate func onGroupPeerExited(groupNumber: UInt32, peerID: UInt32) {
        guard var members = groupPeerNames[groupNumber] else { return }
        members.removeValue(forKey: peerID)
        if members.isEmpty {
            groupPeerNames.removeValue(forKey: groupNumber)
        } else {
            groupPeerNames[groupNumber] = members
        }
        emitGroupMembers(for: groupNumber)
    }

    fileprivate func onGroupCustomPrivatePacket(groupNumber: UInt32, peerID: UInt32, packetData: Data) {
        guard !packetData.isEmpty,
              let payload = String(data: packetData, encoding: .utf8) else {
            return
        }

        if payload.hasPrefix(groupSyncRequestPrefix) {
            onGroupSyncRequestPacket(groupNumber: groupNumber, peerID: peerID, payload: payload)
            return
        }

        if payload.hasPrefix(groupSyncMessagePrefix) {
            onGroupSyncMessagePacket(groupNumber: groupNumber, peerID: peerID, payload: payload)
        }
    }

    fileprivate func onIncomingCall(friendNumber: UInt32) {
        guard let peer = friendToPeer[friendNumber] else {
            refreshPeerList()
            return
        }

        voiceCallStates[peer.id] = .ringingIncoming
        emit(.voiceCallStateChanged(peerID: peer.id, state: .ringingIncoming))
    }

    fileprivate func onCallStateChanged(friendNumber: UInt32, state: UInt32) {
        guard let peer = friendToPeer[friendNumber] else {
            refreshPeerList()
            return
        }

        let resolved: VoiceCallState
        if (state & toxavCallStateError) != 0 || (state & toxavCallStateFinished) != 0 {
            resolved = .idle
        } else {
            resolved = .inCall
        }

        voiceCallStates[peer.id] = resolved
        emit(.voiceCallStateChanged(peerID: peer.id, state: resolved))

        if resolved == .inCall {
            activeCallFriendNumber = friendNumber
            startAudioCaptureIfNeeded(for: friendNumber)
        } else if activeCallFriendNumber == friendNumber {
            activeCallFriendNumber = nil
            callAudioEngine.stopCapture()
        }
    }

    fileprivate func onAudioFrameReceived(friendNumber: UInt32, samples: [Int16], sampleCount: Int, channels: UInt8, sampleRate: UInt32) {
        if activeCallFriendNumber == nil {
            activeCallFriendNumber = friendNumber
        }

        let expected = sampleCount * Int(channels)
        guard expected > 0, samples.count >= expected else { return }
        callAudioEngine.playReceived(samples: Array(samples.prefix(expected)), channels: channels, sampleRate: sampleRate)
    }

    private func startAudioCaptureIfNeeded(for friendNumber: UInt32) {
        callAudioEngine.startCapture { [weak self] samples, channels, sampleRate in
            guard let self else { return }
            Task {
                await self.sendAudioFrame(friendNumber: friendNumber, samples: samples, channels: channels, sampleRate: sampleRate)
            }
        }
    }

    private func sendAudioFrame(friendNumber: UInt32, samples: [Int16], channels: UInt8, sampleRate: UInt32) {
        guard let handle = toxHandle,
              !samples.isEmpty,
              channels > 0,
              activeCallFriendNumber == friendNumber else {
            return
        }

        let perChannelSamples = samples.count / Int(channels)
        guard perChannelSamples > 0 else { return }

        var error: Int32 = 0
        _ = samples.withUnsafeBufferPointer { ptr in
            toxw_av_audio_send_frame(
                handle,
                friendNumber,
                ptr.baseAddress,
                perChannelSamples,
                channels,
                sampleRate,
                &error
            )
        }
    }

    fileprivate func onFileTransferRequest(friendNumber: UInt32, fileNumber: UInt32, kind: UInt32, fileName: String, fileSize: UInt64) {
        let peerID = friendToPeer[friendNumber]?.id ?? stablePeerID(friendNumber: friendNumber)

        let isAvatarKind = kind == toxFileKindAvatar

        if (isAvatarKind || isAvatarTransferFile(name: fileName)), fileSize > 0, fileSize <= 5 * 1024 * 1024,
           let handle = toxHandle,
           let destination = avatarDestinationURL(for: peerID, originalName: fileName) {
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: destination.path, contents: nil)

            if let handleFile = try? FileHandle(forWritingTo: destination) {
                let request = FileTransferRequest(peerID: peerID, friendNumber: friendNumber, fileNumber: fileNumber, fileName: fileName, fileSize: fileSize)
                let context = IncomingFileContext(
                    request: request,
                    destinationURL: destination,
                    handle: handleFile,
                    receivedBytes: 0,
                    isAvatarTransfer: true
                )
                incomingFiles[fileKey(friendNumber: friendNumber, fileNumber: fileNumber)] = context

                var error: Int32 = 0
                _ = toxw_file_control(handle, friendNumber, fileNumber, 0, &error)
                return
            }
        }

        let request = FileTransferRequest(peerID: peerID, friendNumber: friendNumber, fileNumber: fileNumber, fileName: fileName, fileSize: fileSize)
        pendingFileRequests[request.id] = request
        emit(.fileTransferRequestReceived(request))
    }

    fileprivate func onFileChunkReceived(friendNumber: UInt32, fileNumber: UInt32, position: UInt64, chunk: Data, isFinal: Bool) {
        let key = fileKey(friendNumber: friendNumber, fileNumber: fileNumber)
        guard var context = incomingFiles[key] else { return }

        if isFinal {
            try? context.handle.close()
            incomingFiles.removeValue(forKey: key)

            if context.isAvatarTransfer {
                emit(.peerAvatarUpdated(peerID: context.request.peerID, avatarPath: context.destinationURL.path))
                return
            }

            let savedPath = context.destinationURL.path
            let receivedText = l10n.format("message.file.received", context.request.fileName)
            let incomingMessage = ChatMessage(
                peerID: context.request.peerID,
                text: "\(receivedText)\n\(savedPath)",
                isOutgoing: false,
                attachmentURL: context.destinationURL
            )
            emit(.messageReceived(incomingMessage))
            emitTransferPulse(for: context.request.peerID)
            return
        }

        do {
            try context.handle.seek(toOffset: position)
            try context.handle.write(contentsOf: chunk)
            context.receivedBytes += UInt64(chunk.count)
            incomingFiles[key] = context

            let progressValue = min(Double(context.receivedBytes) / Double(max(context.request.fileSize, 1)), 1)
            emit(.fileTransferUpdated(TransferProgress(transferID: context.request.id, peerID: context.request.peerID, progress: progressValue)))
        } catch {
            try? context.handle.close()
            incomingFiles.removeValue(forKey: key)
        }
    }

    fileprivate func onFileChunkRequest(friendNumber: UInt32, fileNumber: UInt32, position: UInt64, length: Int) {
        guard let handle = toxHandle else { return }
        let key = fileKey(friendNumber: friendNumber, fileNumber: fileNumber)
        guard let context = outgoingFiles[key],
              let fileHandle = try? FileHandle(forReadingFrom: context.fileURL) else {
            return
        }

        defer { try? fileHandle.close() }

        do {
            try fileHandle.seek(toOffset: position)
            let chunkData = try fileHandle.read(upToCount: length) ?? Data()
            var err: Int32 = 0
            let sent = chunkData.withUnsafeBytes { buffer in
                toxw_file_send_chunk(
                    handle,
                    friendNumber,
                    fileNumber,
                    position,
                    buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    buffer.count,
                    &err
                )
            }

            if sent, let peerID = friendToPeer[friendNumber]?.id {
                let sentSize = min(position + UInt64(chunkData.count), context.fileSize)
                let progressValue = min(Double(sentSize) / Double(max(context.fileSize, 1)), 1)
                emit(.fileTransferUpdated(TransferProgress(transferID: UUID(), peerID: peerID, progress: progressValue)))
            }
        } catch {
            return
        }
    }

    fileprivate func onFileControl(friendNumber: UInt32, fileNumber: UInt32, control: UInt32) {
        if control == 2 {
            outgoingFiles.removeValue(forKey: fileKey(friendNumber: friendNumber, fileNumber: fileNumber))
            incomingFiles.removeValue(forKey: fileKey(friendNumber: friendNumber, fileNumber: fileNumber))
        }
    }

    private func fileKey(friendNumber: UInt32, fileNumber: UInt32) -> String {
        "\(friendNumber):\(fileNumber)"
    }

    private func downloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private func sendSelfAvatarIfNeeded(to friendNumber: UInt32) {
        guard let handle = toxHandle,
              let selfAvatarPath,
              FileManager.default.fileExists(atPath: selfAvatarPath),
              let avatarURL = normalizedAvatarURL(for: selfAvatarPath) else {
            return
        }

        let fileName = avatarFileName(for: avatarURL)
        _ = sendFile(handle: handle, friendNumber: friendNumber, url: avatarURL, fileNameOverride: fileName, fileKind: toxFileKindAvatar)
    }

    private func normalizedAvatarURL(for path: String) -> URL? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let ext = url.pathExtension.lowercased()
        let allowed = ["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "bmp", "tiff"]
        if ext.isEmpty || allowed.contains(ext) { return url }
        return nil
    }

    private func currentSelfNameData() -> Data? {
        let trimmed = selfDisplayNameCache.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Data("SmoothTox".utf8)
        }
        return Data(trimmed.utf8)
    }

    private func refreshGroupRooms() {
        guard let handle = toxHandle else {
            groupRooms = []
            groupNumberToRoomID = [:]
            groupPeerNames = [:]
            logGroup("rooms refresh skipped: no tox handle")
            emit(.groupRoomsUpdated([]))
            return
        }

        let count = Int(toxw_group_chatlist_size(handle))
        guard count > 0 else {
            if !groupRooms.isEmpty {
                let persisted = Set(loadPersistedGroupChatIDs())
                let filtered = groupRooms.filter { room in
                    guard !room.chatID.isEmpty else { return false }
                    return persisted.contains(room.chatID.uppercased())
                }

                if !filtered.isEmpty {
                    groupRooms = filtered
                    let keptIDs = Set(filtered.map(\.id))
                    groupNumberToRoomID = groupNumberToRoomID.filter { keptIDs.contains($0.value) }
                    groupPeerNames = groupPeerNames.filter { groupNumberToRoomID[$0.key] != nil }
                    logGroup("rooms refresh empty: chatlist_size=0 (keeping \(groupRooms.count) provisional room(s))")
                    emit(.groupRoomsUpdated(groupRooms))
                    return
                }
            }

            groupRooms = []
            groupNumberToRoomID = [:]
            groupPeerNames = [:]
            logGroup("rooms refresh empty: chatlist_size=0")
            emit(.groupRoomsUpdated([]))
            return
        }

        var groupNumbers = [UInt32](repeating: 0, count: count)
        let copied = Int(groupNumbers.withUnsafeMutableBufferPointer { buffer in
            toxw_group_chatlist(handle, buffer.baseAddress, UInt32(buffer.count))
        })

        let chatIDSize = Int(toxw_group_chat_id_size())
        guard chatIDSize > 0 else {
            groupRooms = []
            groupNumberToRoomID = [:]
            groupPeerNames = [:]
            logGroup("rooms refresh failed: invalid chatID size")
            emit(.groupRoomsUpdated([]))
            return
        }

        var nextRooms: [GroupRoom] = []
        var nextMap: [UInt32: UUID] = [:]

        for groupNumber in groupNumbers.prefix(copied) {
            var chatID = [UInt8](repeating: 0, count: chatIDSize)
            var error: Int32 = 0
            let ok = chatID.withUnsafeMutableBufferPointer { ptr in
                toxw_group_get_chat_id(handle, groupNumber, ptr.baseAddress, &error)
            }

            guard ok, error == 0 else { continue }

            let chatIDHex = Data(chatID).hexUppercasedString()
            let roomID = groupNumberToRoomID[groupNumber] ?? UUID()
            nextMap[groupNumber] = roomID

            let existingRoom = groupRooms.first(where: { $0.id == roomID })
            let existingName = existingRoom?.name
            let fallbackName = "Group \(chatIDHex.prefix(10))"
            let room = GroupRoom(
                id: roomID,
                name: existingName ?? fallbackName,
                chatID: chatIDHex,
                isHost: existingRoom?.isHost ?? false
            )
            nextRooms.append(room)
        }

        groupRooms = nextRooms
        groupNumberToRoomID = nextMap
        let activeNumbers = Set(nextMap.keys)
        groupPeerNames = groupPeerNames.filter { activeNumbers.contains($0.key) }
        emit(.groupRoomsUpdated(nextRooms))
        logGroup("rooms refreshed count=\(nextRooms.count)")
        if hasConnectedOnce, !nextRooms.isEmpty {
            savePersistedGroupChatIDs(nextRooms.map(\ .chatID).filter { !$0.isEmpty })
        }
        for groupNumber in nextMap.keys {
            emitGroupMembers(for: groupNumber)
        }
    }

    private func sendHistorySyncRequestIfNeeded(groupNumber: UInt32, peerID: UInt32) async {
        guard isRunning,
              let handle = toxHandle,
              groupNumberToRoomID[groupNumber] != nil,
              isPublicGroup(groupNumber: groupNumber) else {
            return
        }

        if isSelfPeer(groupNumber: groupNumber, peerID: peerID) {
            return
        }

        let payload = "\(groupSyncRequestPrefix)\(groupSyncDefaultDeltaMinutes)"
        guard let data = payload.data(using: .utf8) else { return }

        var error: Int32 = 0
        let ok = data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            return toxw_group_send_custom_private_packet(handle, groupNumber, peerID, true, base, buffer.count, &error)
        }

        logGroup("sync request send groupNumber=\(groupNumber) peerID=\(peerID) ok=\(ok) error=\(error)")
    }

    private func onGroupSyncRequestPacket(groupNumber: UInt32, peerID: UInt32, payload: String) {
        guard isPublicGroup(groupNumber: groupNumber),
              let groupID = groupNumberToRoomID[groupNumber],
              let group = groupRooms.first(where: { $0.id == groupID }) else {
            return
        }

        let suffix = String(payload.dropFirst(groupSyncRequestPrefix.count))
        let requestedDelta = UInt8(suffix) ?? groupSyncDefaultDeltaMinutes
        let requesterName = resolveGroupPeerName(groupNumber: groupNumber, peerID: peerID)
        let request = GroupHistorySyncRequest(
            groupID: groupID,
            groupName: group.name,
            requesterName: requesterName,
            syncDeltaMinutes: requestedDelta
        )

        pendingGroupSyncAuthorizations[request.id] = GroupSyncAuthorizationContext(
            id: request.id,
            groupNumber: groupNumber,
            requesterPeerID: peerID,
            deltaMinutes: requestedDelta
        )

        logGroup("sync auth request queued groupNumber=\(groupNumber) peerID=\(peerID) delta=\(requestedDelta)")
        emit(.groupHistorySyncAuthorizationRequested(request))
    }

    private func onGroupSyncMessagePacket(groupNumber: UInt32, peerID: UInt32, payload: String) {
        guard let groupID = groupNumberToRoomID[groupNumber],
              isPublicGroup(groupNumber: groupNumber) else {
            return
        }

        let body = String(payload.dropFirst(groupSyncMessagePrefix.count))
        let parts = body.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let timestampSec = TimeInterval(parts[0]),
              let senderData = Data(base64Encoded: String(parts[1])),
              let textData = Data(base64Encoded: String(parts[2])),
              let senderName = String(data: senderData, encoding: .utf8),
              let text = String(data: textData, encoding: .utf8),
              !text.isEmpty else {
            return
        }

        let timestamp = Date(timeIntervalSince1970: timestampSec)
        guard abs(Date.now.timeIntervalSince(timestamp)) <= groupSyncMaxHistoryWindow else {
            return
        }

        guard registerSeenGroupMessage(groupID: groupID, senderName: senderName, text: text, timestamp: timestamp) else {
            return
        }

        setGroupPeerName(groupNumber: groupNumber, peerID: peerID, name: senderName)
        appendGroupHistoryEntry(groupID: groupID, timestamp: timestamp, senderName: senderName, text: text)
        emitGroupMembers(for: groupNumber)
        emit(.groupMessageReceived(groupID: groupID, senderName: senderName, text: text))
    }

    private func sendGroupHistorySync(to peerID: UInt32, groupNumber: UInt32, deltaMinutes: UInt8) async {
        guard let handle = toxHandle,
              let groupID = groupNumberToRoomID[groupNumber],
              isPublicGroup(groupNumber: groupNumber) else {
            return
        }

        let deltaSeconds = max(60.0, TimeInterval(deltaMinutes) * 60.0)
        let cutoff = Date.now.addingTimeInterval(-deltaSeconds)
        let entries = groupHistoryByRoomID[groupID, default: []]
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        if entries.isEmpty {
            logGroup("sync send skipped groupNumber=\(groupNumber) peerID=\(peerID) reason=no_entries")
            return
        }

        for entry in entries {
            let senderB64 = Data(entry.senderName.utf8).base64EncodedString()
            let textB64 = Data(entry.text.utf8).base64EncodedString()
            let payload = "\(groupSyncMessagePrefix)\(entry.timestamp.timeIntervalSince1970)|\(senderB64)|\(textB64)"
            guard let data = payload.data(using: .utf8) else { continue }

            var error: Int32 = 0
            let sent = data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
                return toxw_group_send_custom_private_packet(handle, groupNumber, peerID, true, base, buffer.count, &error)
            }

            if !sent || error != 0 {
                logGroup("sync send failed groupNumber=\(groupNumber) peerID=\(peerID) error=\(error)")
                return
            }
        }

        logGroup("sync send completed groupNumber=\(groupNumber) peerID=\(peerID) count=\(entries.count)")
    }

    private func emitPendingGroupInvites() {
        let ordered = pendingGroupInvites.values
            .map(\.request)
            .sorted { lhs, rhs in
                if lhs.groupName == rhs.groupName {
                    return lhs.inviterName < rhs.inviterName
                }
                return lhs.groupName < rhs.groupName
            }
        emit(.groupInvitesUpdated(ordered))
    }

    private func resolveGroupPeerName(groupNumber: UInt32, peerID: UInt32) -> String {
        tryResolveGroupPeerName(groupNumber: groupNumber, peerID: peerID) ?? "Peer #\(peerID)"
    }

    private func tryResolveGroupPeerName(groupNumber: UInt32, peerID: UInt32) -> String? {
        guard let handle = toxHandle else { return nil }

        var size: Int = 128
        var bytes = [UInt8](repeating: 0, count: size)
        let success = bytes.withUnsafeMutableBufferPointer { buffer in
            toxw_group_peer_get_name(handle, groupNumber, peerID, buffer.baseAddress, &size)
        }

        if !success, size > bytes.count {
            bytes = [UInt8](repeating: 0, count: size)
            let retried = bytes.withUnsafeMutableBufferPointer { buffer in
                toxw_group_peer_get_name(handle, groupNumber, peerID, buffer.baseAddress, &size)
            }
            guard retried else { return nil }
        } else if !success {
            return nil
        }

        guard size > 0,
              size <= bytes.count,
              let name = String(data: Data(bytes[0..<size]), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }

        return name
    }

    private func setGroupPeerName(groupNumber: UInt32, peerID: UInt32, name: String) {
        var members = groupPeerNames[groupNumber, default: [:]]
        members[peerID] = name
        groupPeerNames[groupNumber] = members
    }

    private func appendGroupHistoryEntry(groupID: UUID, timestamp: Date, senderName: String, text: String) {
        var entries = groupHistoryByRoomID[groupID, default: []]
        entries.append(GroupHistoryEntry(timestamp: timestamp, senderName: senderName, text: text))
        if entries.count > 5000 {
            entries.removeFirst(entries.count - 5000)
        }
        groupHistoryByRoomID[groupID] = entries
    }

    private func registerSeenGroupMessage(groupID: UUID, senderName: String, text: String, timestamp: Date) -> Bool {
        let rounded = Int(timestamp.timeIntervalSince1970)
        let key = "\(rounded)|\(senderName)|\(text)"
        var map = seenGroupMessageKeys[groupID, default: [:]]

        let now = Date.now
        map = map.filter { now.timeIntervalSince($0.value) <= groupSyncMaxHistoryWindow }
        if map[key] != nil {
            seenGroupMessageKeys[groupID] = map
            return false
        }

        map[key] = now
        seenGroupMessageKeys[groupID] = map
        return true
    }

    private func isPublicGroup(groupNumber: UInt32) -> Bool {
        guard let handle = toxHandle else { return false }
        var isPublic = false
        var error: Int32 = 0
        let ok = toxw_group_is_public(handle, groupNumber, &isPublic, &error)
        return ok && error == 0 && isPublic
    }

    private func isSelfPeer(groupNumber: UInt32, peerID: UInt32) -> Bool {
        guard let handle = toxHandle else { return false }

        var selfKey = [UInt8](repeating: 0, count: 32)
        var peerKey = [UInt8](repeating: 0, count: 32)

        let gotSelf = selfKey.withUnsafeMutableBufferPointer { ptr in
            toxw_group_self_get_public_key(handle, groupNumber, ptr.baseAddress)
        }
        let gotPeer = peerKey.withUnsafeMutableBufferPointer { ptr in
            toxw_group_peer_get_public_key(handle, groupNumber, peerID, ptr.baseAddress)
        }

        return gotSelf && gotPeer && selfKey == peerKey
    }

    private func emitGroupMembers(for groupNumber: UInt32) {
        guard let groupID = groupNumberToRoomID[groupNumber] else { return }

        let remoteMembers = (groupPeerNames[groupNumber] ?? [:])
            .sorted { lhs, rhs in
                lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
            }
            .map { GroupMember(id: "\($0.key)", displayName: $0.value) }

        let selfMember = GroupMember(id: "self", displayName: selfDisplayNameCache)
        emit(.groupMembersUpdated(groupID: groupID, members: [selfMember] + remoteMembers))
    }

    private func refreshGroupRoomsWithRetry() async {
        let delays: [UInt64] = [250, 600, 1200, 2200]
        for delay in delays {
            try? await Task.sleep(for: .milliseconds(Int(delay)))
            if !isRunning { return }
            refreshGroupRooms()
        }
    }

    private func hydrateAllVisibleGroupPeers() async {
        let groupNumbers = Array(groupNumberToRoomID.keys)
        guard !groupNumbers.isEmpty else { return }

        for groupNumber in groupNumbers {
            await hydrateGroupPeers(groupNumber: groupNumber)
        }
    }

    private func hydrateGroupPeers(groupNumber: UInt32) async {
        let delays: [UInt64] = [250, 900, 1800]
        for delay in delays {
            try? await Task.sleep(for: .milliseconds(Int(delay)))
            if !isRunning { return }
            guard groupNumberToRoomID[groupNumber] != nil else { return }

            let discovered = discoverGroupPeerNames(groupNumber: groupNumber)
            if discovered.isEmpty { continue }

            var members = groupPeerNames[groupNumber, default: [:]]
            for (peerID, name) in discovered {
                members[peerID] = name
            }
            groupPeerNames[groupNumber] = members
            emitGroupMembers(for: groupNumber)
            logGroup("peer hydration groupNumber=\(groupNumber) found=\(discovered.count)")
        }
    }

    private func discoverGroupPeerNames(groupNumber: UInt32) -> [UInt32: String] {
        let maxProbe: UInt32 = 512
        var found: [UInt32: String] = [:]
        var missesInARow = 0

        for peerID in 0..<maxProbe {
            if let name = tryResolveGroupPeerName(groupNumber: groupNumber, peerID: peerID) {
                found[peerID] = name
                missesInARow = 0
            } else {
                missesInARow += 1
                if !found.isEmpty && missesInARow >= 32 {
                    break
                }
                if found.isEmpty && peerID >= 96 {
                    break
                }
            }
        }

        return found
    }

    private func autoRejoinPersistedGroupsIfNeeded() async {
        guard isRunning,
              hasConnectedOnce,
              let handle = toxHandle,
              let selfName = currentSelfNameData() else {
            return
        }

        let persisted = loadPersistedGroupChatIDs()
        guard !persisted.isEmpty else { return }
        logGroup("auto-rejoin start persistedCount=\(persisted.count)")

        let existing = Set(groupRooms.map { $0.chatID.uppercased() })
        var joinedAny = false

        for chatIDHex in persisted {
            let normalized = chatIDHex.uppercased()
            if existing.contains(normalized) { continue }

            guard let chatID = Data(hexString: normalized),
                  chatID.count == Int(toxw_group_chat_id_size()) else {
                continue
            }

            var groupNumber: UInt32 = 0
            var error: Int32 = 0
            let joined = chatID.withUnsafeBytes { chatBuffer in
                selfName.withUnsafeBytes { selfBuffer in
                    guard let chatBase = chatBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let selfBase = selfBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return false
                    }

                    return toxw_group_join_by_chat_id(
                        handle,
                        chatBase,
                        chatBuffer.count,
                        selfBase,
                        selfBuffer.count,
                        &groupNumber,
                        &error
                    )
                }
            }

            if joined, error == 0 {
                joinedAny = true
                let provisionalID = groupNumberToRoomID[groupNumber] ?? UUID()
                groupNumberToRoomID[groupNumber] = provisionalID

                if let index = groupRooms.firstIndex(where: { $0.id == provisionalID }) {
                    let current = groupRooms[index]
                    groupRooms[index] = GroupRoom(
                        id: current.id,
                        name: current.name,
                        chatID: current.chatID.isEmpty ? normalized : current.chatID,
                        isHost: current.isHost
                    )
                } else {
                    groupRooms.append(
                        GroupRoom(
                            id: provisionalID,
                            name: "Group \(normalized.prefix(10))",
                            chatID: normalized,
                            isHost: false
                        )
                    )
                }
                emit(.groupRoomsUpdated(groupRooms))
                logGroup("auto-rejoin success groupNumber=\(groupNumber) chatID=\(normalized.prefix(16))…")
            } else {
                logGroup("auto-rejoin failed error=\(error) chatID=\(normalized.prefix(16))…")
            }
        }

        if joinedAny {
            refreshGroupRooms()
            await refreshGroupRoomsWithRetry()
            logGroup("auto-rejoin completed with updates")
        }
    }

    private func logGroup(_ message: String) {
        guard groupLogsEnabled else { return }
        print("[GroupFlow] \(message)")
    }

    private func loadPersistedGroupChatIDs() -> [String] {
        let raw = UserDefaults.standard.array(forKey: persistedGroupChatIDsKey) as? [String] ?? []
        return raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
    }

    private func savePersistedGroupChatIDs(_ chatIDs: [String]) {
        let normalized = Array(Set(chatIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty }))
            .sorted()
        UserDefaults.standard.set(normalized, forKey: persistedGroupChatIDsKey)
    }

    private func appendPersistedGroupChatID(_ chatID: String) {
        let normalized = chatID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }
        var existing = loadPersistedGroupChatIDs()
        if !existing.contains(normalized) {
            existing.append(normalized)
            savePersistedGroupChatIDs(existing)
        }
    }

    private func removePersistedGroupChatID(_ chatID: String) {
        let normalized = chatID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }
        let filtered = loadPersistedGroupChatIDs().filter { $0 != normalized }
        savePersistedGroupChatIDs(filtered)
    }

    private func avatarFileName(for url: URL) -> String {
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        return "\(avatarFilePrefix).\(ext)"
    }

    private func isAvatarTransferFile(name: String) -> Bool {
        name.lowercased().hasPrefix(avatarFilePrefix)
    }

    private func avatarDestinationURL(for peerID: UUID, originalName: String) -> URL? {
        let ext = URL(fileURLWithPath: originalName).pathExtension.lowercased()
        let finalExt = ext.isEmpty ? "png" : ext
        return avatarsDirectory().appendingPathComponent("\(peerID.uuidString.lowercased()).\(finalExt)")
    }

    private func avatarsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("SmoothTox", isDirectory: true)
            .appendingPathComponent("PeerAvatars", isDirectory: true)
    }
}

private extension Data {
    init?(hexString: String) {
        let raw = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(raw.count / 2)

        var index = raw.startIndex
        while index < raw.endIndex {
            let next = raw.index(index, offsetBy: 2)
            let byteString = raw[index..<next]
            guard let value = UInt8(byteString, radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }

        self = Data(bytes)
    }

    func hexUppercasedString() -> String {
        map { String(format: "%02X", $0) }.joined()
    }
}