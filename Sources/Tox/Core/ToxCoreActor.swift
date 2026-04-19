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
    private let appConfig = BootstrapConfigLoader.loadFromBundle()
    private let userProfileStore = UserProfileStore()
    private var selfAvatarPath: String?
    private var isRunning = false
    private let avatarFilePrefix = "smoothtox-avatar-v1"
    private let avatarClearControlMessage = "[[SMOOTHTOX_AVATAR_CLEAR_V1]]"
    private let toxFileKindData: UInt32 = 0
    private let toxFileKindAvatar: UInt32 = 1

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

        bootstrapFromConfig()
        emitSelfAddressIfAvailable()
        emitSelfDisplayNameIfAvailable()
        selfAvatarPath = userProfileStore.loadAvatarPath()
        refreshPeerList()

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

        eventContinuation.yield(.peerListUpdated([]))
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

        profileStore.resetAll()
        eventContinuation.yield(.peerListUpdated([]))
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
        emit(.connectionStateChanged(state))
        emitSelfAddressIfAvailable()
    }

    fileprivate func onFriendConnectionStatus(friendNumber: UInt32, connectionStatus: UInt32) {
        if connectionStatus > 0 {
            refreshPeerList()
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
            let incomingMessage = ChatMessage(
                peerID: context.request.peerID,
                text: "Dosya alındı: \(context.request.fileName)\n\(savedPath)",
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