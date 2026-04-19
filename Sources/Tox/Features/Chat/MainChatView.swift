import SwiftUI
import AppKit

struct MainChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var composerHeight: CGFloat = 36
    private let uiConfig = BootstrapConfigLoader.loadFromBundle().ui

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 10) {
                sidebarTopHeader
                pendingRequestsSection

                List(selection: Binding(
                    get: { viewModel.selectedPeerID },
                    set: { newValue in
                        if let newValue {
                            viewModel.selectPeer(newValue)
                        }
                    }
                )) {
                    ForEach(viewModel.peers) { peer in
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
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    openAttachmentPicker()
                } label: {
                    Label("Dosya Ata", systemImage: "paperclip")
                }

                Button {
                    viewModel.copySelfToxID()
                } label: {
                    Label("ID Kopyala", systemImage: viewModel.didCopyToxID ? "checkmark" : "doc.on.doc")
                }

                Button {
                    viewModel.openAddFriendDialog()
                } label: {
                    Label("Arkadaş Ekle", systemImage: "person.badge.plus")
                }

                Button {
                    viewModel.openProfileSettings()
                } label: {
                    Label("Profil", systemImage: "person.crop.circle")
                }

                Button {
                    exportProfile()
                } label: {
                    Label("Dışa Aktar", systemImage: "square.and.arrow.up")
                }

                Button {
                    openDownloadsFolder()
                } label: {
                    Label("İndirilenler", systemImage: "folder")
                }

                Button(role: .destructive) {
                    viewModel.isResetConfirmationPresented = true
                } label: {
                    Label("ID/DB Sıfırla", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $viewModel.isAddFriendSheetPresented) {
            addFriendSheet
        }
        .sheet(isPresented: $viewModel.isProfileSheetPresented) {
            profileSettingsSheet
        }
        .alert("Kimlik ve Veritabanı Sıfırlansın mı?", isPresented: $viewModel.isResetConfirmationPresented) {
            Button("İptal", role: .cancel) { }
            Button("Sıfırla", role: .destructive) {
                viewModel.resetIdentityAndDatabase()
            }
        } message: {
            Text("Bu işlem yeni bir Tox kimliği oluşturur ve mevcut profil verisini temizler.")
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
            Text("Arkadaşlık İsteği Gönder")
                .font(.headline)

            TextField("Tox ID", text: $viewModel.addFriendIDInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("İptal") {
                    viewModel.isAddFriendSheetPresented = false
                }
                Button("Gönder") {
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
            Text("Profil Ayarları")
                .font(.headline)

            HStack(spacing: 12) {
                AvatarView(name: viewModel.profileDraftName, imagePath: viewModel.profileDraftAvatarPath, size: 56)

                VStack(alignment: .leading, spacing: 8) {
                    Button("Fotoğraf Seç") {
                        openProfileImagePicker()
                    }
                    .buttonStyle(.bordered)

                    Button("Fotoğrafı Kaldır", role: .destructive) {
                        viewModel.clearProfileDraftAvatar()
                    }
                    .buttonStyle(.bordered)
                }
            }

            TextField("Görünen isim", text: $viewModel.profileDraftName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("İptal") {
                    viewModel.isProfileSheetPresented = false
                }
                Button("Kaydet") {
                    viewModel.saveProfileSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }
        }
        .padding(16)
        .frame(minWidth: 460)
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
        panel.title = "Dosya Ata"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.sendFile(url: url)
    }

    private func openProfileImagePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.title = "Fotoğraf Seç"

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
            if !viewModel.pendingFriendRequests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gelen İstekler")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.pendingFriendRequests.prefix(3)) { request in
                        HStack(spacing: 8) {
                            Text(request.publicKeyHex)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 6)

                            Button("Kabul") {
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
                    Text("Dosya İstekleri")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.pendingFileRequests.prefix(3)) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.fileName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text("\(request.fileSize) bytes • Kabul edilince Downloads klasörüne iner")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Reddet", role: .destructive) {
                                    viewModel.rejectFileRequest(request)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Kabul") {
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
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: viewModel.pendingFriendRequests)
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: viewModel.pendingFileRequests)
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

            TextField("Mesajlarda ara", text: $viewModel.messageSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            if viewModel.connectionState == .connecting {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.connectionState == .online {
                Label("Synced", systemImage: "checkmark.icloud")
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