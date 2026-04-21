import SwiftUI
import AppKit

struct MainChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var composerHeight: CGFloat = 36
    private let uiConfig = BootstrapConfigLoader.loadFromBundle().ui
    private let l10n = AppLocalizer.shared

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 10) {
                sidebarTopHeader
                TextField(l10n.text("sidebar.search"), text: $viewModel.peerSearchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 6)
                pendingRequestsSection
                groupsSection

                List(selection: Binding(
                    get: { viewModel.selectedGroupID ?? viewModel.selectedPeerID },
                    set: { newValue in
                        if let newValue {
                            if viewModel.groupRooms.contains(where: { $0.id == newValue }) {
                                viewModel.selectGroup(newValue)
                            } else {
                                viewModel.selectPeer(newValue)
                            }
                        }
                    }
                )) {
                    ForEach(viewModel.visibleGroups) { room in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.green.opacity(0.75), .blue.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)

                                Text(room.isHost ? l10n.text("group.host.badge") : l10n.text("group.join.action"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .tag(room.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        .listRowBackground(Color.clear)
                    }

                    ForEach(viewModel.visiblePeers) { peer in
                        HStack(spacing: 10) {
                            AvatarView(name: peer.displayName, imagePath: viewModel.avatarPath(for: peer.id), size: 32)

                            Text(peer.displayName)
                                .font(.body.weight(.medium))
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .tag(peer.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.sidebar)
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .padding(10)
        } detail: {
            VStack(spacing: 0) {
                header
                if viewModel.selectedGroupID != nil {
                    Divider().opacity(0.35)
                    groupMembersBar
                }
                Divider().opacity(0.35)
                chatBody
                Divider().opacity(0.35)
                composer
            }
            .background(
                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(minWidth: 980, minHeight: 640)
        .task {
            viewModel.bootstrap()
        }
        .onDisappear {
            viewModel.shutdown()
        }
        .overlay(alignment: .top) {
            if viewModel.isIncomingCallPopupVisible {
                incomingCallPopup
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    openAttachmentPicker()
                } label: {
                    Label(l10n.text("toolbar.attach"), systemImage: "paperclip")
                }

                Button {
                    viewModel.copySelfToxID()
                } label: {
                    Label(l10n.text("toolbar.copyID"), systemImage: viewModel.didCopyToxID ? "checkmark" : "doc.on.doc")
                }

                Button {
                    viewModel.openAddFriendDialog()
                } label: {
                    Label(l10n.text("toolbar.addFriend"), systemImage: "person.badge.plus")
                }

                Button {
                    viewModel.openProfileSettings()
                } label: {
                    Label(l10n.text("toolbar.profile"), systemImage: "person.crop.circle")
                }

                Button {
                    switch viewModel.selectedPeerCallState {
                    case .ringingIncoming:
                        viewModel.acceptCallFromSelectedPeer()
                    case .ringingOutgoing, .inCall:
                        viewModel.endCallWithSelectedPeer()
                    case .idle:
                        viewModel.startCallWithSelectedPeer()
                    }
                } label: {
                    Label(callToolbarTitle, systemImage: callToolbarIcon)
                }

                Button {
                    viewModel.openHostGroupDialog()
                } label: {
                    Label(l10n.text("toolbar.hostGroup"), systemImage: "person.3.sequence")
                }

                Button {
                    viewModel.openJoinGroupDialog()
                } label: {
                    Label(l10n.text("toolbar.joinGroup"), systemImage: "person.3")
                }

                Button {
                    exportProfile()
                } label: {
                    Label(l10n.text("toolbar.export"), systemImage: "square.and.arrow.up")
                }

                Button {
                    openDownloadsFolder()
                } label: {
                    Label(l10n.text("toolbar.downloads"), systemImage: "folder")
                }

                Button(role: .destructive) {
                    viewModel.isResetConfirmationPresented = true
                } label: {
                    Label(l10n.text("toolbar.reset"), systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $viewModel.isAddFriendSheetPresented) {
            addFriendSheet
        }
        .sheet(isPresented: $viewModel.isProfileSheetPresented) {
            profileSettingsSheet
        }
        .sheet(isPresented: $viewModel.isHostGroupSheetPresented) {
            hostGroupSheet
        }
        .sheet(isPresented: $viewModel.isJoinGroupSheetPresented) {
            joinGroupSheet
        }
        .alert(l10n.text("alert.reset.title"), isPresented: $viewModel.isResetConfirmationPresented) {
            Button(l10n.text("alert.cancel"), role: .cancel) { }
            Button(l10n.text("alert.reset.confirm"), role: .destructive) {
                viewModel.resetIdentityAndDatabase()
            }
        } message: {
            Text(l10n.text("alert.reset.message"))
        }
    }

    private var incomingCallPopup: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.bubble.left.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.text("call.incoming.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.incomingCallPeerName)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button(l10n.text("call.decline"), role: .destructive) {
                viewModel.declineIncomingCallFromPopup()
            }
            .buttonStyle(.bordered)

            Button(l10n.text("call.accept")) {
                viewModel.acceptIncomingCallFromPopup()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .padding(.horizontal, 16)
    }

    private var callToolbarTitle: String {
        switch viewModel.selectedPeerCallState {
        case .ringingIncoming:
            return l10n.text("call.accept")
        case .ringingOutgoing, .inCall:
            return l10n.text("call.end")
        case .idle:
            return l10n.text("call.start")
        }
    }

    private var callToolbarIcon: String {
        switch viewModel.selectedPeerCallState {
        case .ringingIncoming:
            return "phone.arrow.down.left"
        case .ringingOutgoing, .inCall:
            return "phone.down"
        case .idle:
            return "phone"
        }
    }

    private var sidebarTopHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarView(name: viewModel.selfDisplayName, imagePath: viewModel.selfAvatarPath, size: 28)

                Text(viewModel.selfToxID)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                Button {
                    viewModel.copySelfToxID()
                } label: {
                    Image(systemName: viewModel.didCopyToxID ? "checkmark" : "doc.on.doc")
                        .symbolEffect(.bounce, value: viewModel.didCopyToxID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private var addFriendSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.text("sheet.addFriend.title"))
                .font(.headline)

            TextField(l10n.text("sheet.addFriend.toxID"), text: $viewModel.addFriendIDInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(l10n.text("alert.cancel")) {
                    viewModel.isAddFriendSheetPresented = false
                }
                Button(l10n.text("sheet.send")) {
                    viewModel.submitAddFriend()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }
        }
        .padding(16)
        .frame(minWidth: 420)
    }

    private var profileSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.text("sheet.profile.title"))
                .font(.headline)

            HStack(spacing: 12) {
                AvatarView(name: viewModel.profileDraftName, imagePath: viewModel.profileDraftAvatarPath, size: 56)

                VStack(alignment: .leading, spacing: 8) {
                    Button(l10n.text("sheet.profile.pickPhoto")) {
                        openProfileImagePicker()
                    }
                    .buttonStyle(.bordered)

                    Button(l10n.text("sheet.profile.removePhoto"), role: .destructive) {
                        viewModel.clearProfileDraftAvatar()
                    }
                    .buttonStyle(.bordered)
                }
            }

            TextField(l10n.text("sheet.profile.displayName"), text: $viewModel.profileDraftName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(l10n.text("alert.cancel")) {
                    viewModel.isProfileSheetPresented = false
                }
                Button(l10n.text("sheet.save")) {
                    viewModel.saveProfileSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }
        }
        .padding(16)
        .frame(minWidth: 460)
    }

    private var hostGroupSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.text("group.host.title"))
                .font(.headline)

            TextField(l10n.text("group.host.name"), text: $viewModel.hostGroupNameInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(l10n.text("alert.cancel")) {
                    viewModel.isHostGroupSheetPresented = false
                }
                Button(l10n.text("group.host.action")) {
                    viewModel.submitHostGroup()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420)
    }

    private var joinGroupSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.text("group.join.title"))
                .font(.headline)

            TextField(l10n.text("group.join.invite"), text: $viewModel.joinGroupInviteInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(l10n.text("alert.cancel")) {
                    viewModel.isJoinGroupSheetPresented = false
                }
                Button(l10n.text("group.join.action")) {
                    viewModel.submitJoinGroup()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420)
    }

    private func exportProfile() {
        Task {
            guard let data = await viewModel.exportProfileData(), !data.isEmpty else { return }

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.data]
            savePanel.nameFieldStringValue = "smoothtox-profile.tox"
            savePanel.canCreateDirectories = true

            let response = savePanel.runModal()
            guard response == .OK, let url = savePanel.url else { return }

            try? data.write(to: url, options: .atomic)
        }
    }

    private func openAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = l10n.text("panel.attach.title")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.sendFile(url: url)
    }

    private func openProfileImagePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.title = l10n.text("panel.photo.title")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.setProfileDraftAvatar(url: url)
    }

    private func openDownloadsFolder() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let downloads {
            NSWorkspace.shared.open(downloads)
        }
    }

    private var pendingRequestsSection: some View {
        VStack(spacing: 10) {
            if !viewModel.pendingGroupInvites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.text("pending.groupInvites"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.pendingGroupInvites.prefix(3)) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.groupName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            Text(l10n.format("pending.group.from", request.inviterName))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack {
                                Button(l10n.text("pending.reject"), role: .destructive) {
                                    viewModel.rejectGroupInvite(request)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(l10n.text("pending.accept")) {
                                    viewModel.acceptGroupInvite(request)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !viewModel.pendingFriendRequests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.text("pending.friendRequests"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.pendingFriendRequests.prefix(3)) { request in
                        HStack(spacing: 8) {
                            Text(request.publicKeyHex)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 6)

                            Button(l10n.text("pending.accept")) {
                                viewModel.acceptFriendRequest(request)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !viewModel.pendingFileRequests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.text("pending.fileRequests"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.pendingFileRequests.prefix(3)) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.fileName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(l10n.format("pending.file.hint", request.fileSize))
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button(l10n.text("pending.reject"), role: .destructive) {
                                    viewModel.rejectFileRequest(request)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(l10n.text("pending.accept")) {
                                    viewModel.acceptFileRequest(request)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: viewModel.pendingGroupInvites)
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: viewModel.pendingFriendRequests)
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: viewModel.pendingFileRequests)
    }

    private var groupsSection: some View {
        Group {
            if !viewModel.groupRooms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.text("group.section.title"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.groupRooms) { room in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(room.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if room.isHost {
                                    Text(l10n.text("group.host.badge"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                Text(room.chatID)
                                    .font(.caption2.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer(minLength: 6)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(room.chatID, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(l10n.text("group.leave"), role: .destructive) {
                                    viewModel.leaveGroup(room)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(viewModel.selectedGroupID == room.id ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1.5)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onTapGesture {
                            viewModel.selectGroup(room.id)
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbolName)
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse.byLayer, options: .repeating, isActive: viewModel.connectionState == .connecting)
                .symbolEffect(.bounce, value: viewModel.connectionState)

            Text(viewModel.selectedPeerName)
                .font(.headline)

            Spacer()

            TextField(l10n.text("header.search"), text: $viewModel.messageSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            if viewModel.connectionState == .connecting {
                ProgressView()
                    .controlSize(.small)
                Text(l10n.text("header.syncing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.connectionState == .online {
                Label(l10n.text("header.synced"), systemImage: "checkmark.icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var chatBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.visibleMessages) { message in
                        MessageBubble(message: message, minimumHeight: CGFloat(uiConfig.messageBubbleMinHeight))
                            .id(message.id)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .padding(12)
            }
            .onChange(of: viewModel.visibleMessages.count) { _, _ in
                guard viewModel.isUserNearBottom,
                      let lastID = viewModel.visibleMessages.last?.id else { return }

                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var groupMembersBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l10n.text("group.members.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(viewModel.selectedGroupMembers.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.selectedGroupMembers) { member in
                        Text(member.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button {
                openAttachmentPicker()
            } label: {
                Image(systemName: "paperclip")
            }
            .buttonStyle(.bordered)

            MessageInputTextView(
                text: $viewModel.draftMessage,
                dynamicHeight: $composerHeight,
                onSend: {
                    viewModel.sendCurrentMessage()
                }
            )
                .frame(height: composerHeight)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                viewModel.sendCurrentMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .scaleEffect(viewModel.draftMessage.isEmpty ? 0.98 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: viewModel.draftMessage.isEmpty)
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var statusSymbolName: String {
        switch viewModel.connectionState {
        case .offline:
            return "wifi.slash"
        case .connecting:
            return "dot.radiowaves.left.and.right"
        case .online:
            return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .offline:
            return .secondary
        case .connecting:
            return .orange
        case .online:
            return .green
        }
    }
}

private struct AvatarView: View {
    let name: String
    let imagePath: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let imagePath,
               !imagePath.isEmpty,
               let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.75), .purple.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Text(initials)
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let parts = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
        let chars = parts.compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars)
    }
}

private struct MessageInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, dynamicHeight: $dynamicHeight, onSend: onSend)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.documentView = textView

        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var dynamicHeight: CGFloat
        let onSend: () -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, dynamicHeight: Binding<CGFloat>, onSend: @escaping () -> Void) {
            _text = text
            _dynamicHeight = dynamicHeight
            self.onSend = onSend
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            text = tv.string
            Task { @MainActor [weak self] in
                self?.recalculateHeight()
            }
        }

        @MainActor
        func recalculateHeight() {
            guard let tv = textView,
                  let layoutManager = tv.layoutManager,
                  let textContainer = tv.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer).height
            let target = min(max(used + 10, 30), 120)
            if abs(dynamicHeight - target) > 0.5 {
                dynamicHeight = target
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    onSend()
                }
                return true
            }
            return false
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let minimumHeight: CGFloat

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer(minLength: 44)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let url = message.attachmentURL {
                    AttachmentPreview(url: url)
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: minimumHeight, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            )
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)

            if !message.isOutgoing {
                Spacer(minLength: 44)
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: message.id)
    }
}

private struct AttachmentPreview: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url), isLikelyImage(url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func isLikelyImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff"].contains(url.pathExtension.lowercased())
    }
}