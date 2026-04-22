import AppKit
import SwiftUI

@main
enum SmoothToxApp {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()

        application.setActivationPolicy(.regular)
        application.delegate = appDelegate
        application.activate(ignoringOtherApps: true)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let viewModel = ChatViewModel(toxClient: ToxCoreActor())

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        let contentView = MainChatView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "SmoothTox"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = buildAppMenu()

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        fileItem.submenu = buildFileMenu()

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        editItem.submenu = buildEditMenu()

        let peersItem = NSMenuItem()
        mainMenu.addItem(peersItem)
        peersItem.submenu = buildPeersMenu()

        let groupsItem = NSMenuItem()
        mainMenu.addItem(groupsItem)
        groupsItem.submenu = buildGroupsMenu()

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        windowItem.submenu = buildWindowMenu()
    }

    private func buildAppMenu() -> NSMenu {
        let menu = NSMenu(title: "Tox")

        let about = NSMenuItem(title: "About SmoothTox", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = NSApp
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SmoothTox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    private func buildFileMenu() -> NSMenu {
        let menu = NSMenu(title: "Profile")

        let profile = NSMenuItem(title: "Profile Settings…", action: #selector(menuOpenProfileSettings(_:)), keyEquivalent: ",")
        profile.target = self
        menu.addItem(profile)

        let export = NSMenuItem(title: "Export Profile…", action: #selector(menuExportProfile(_:)), keyEquivalent: "e")
        export.keyEquivalentModifierMask = [.command, .shift]
        export.target = self
        menu.addItem(export)

        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Reset Identity/DB…", action: #selector(menuResetIdentity(_:)), keyEquivalent: "r")
        reset.keyEquivalentModifierMask = [.command, .shift]
        reset.target = self
        menu.addItem(reset)

        return menu
    }

    private func buildEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")

        let undo = NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        undo.target = nil
        menu.addItem(undo)

        let redo = NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = nil
        menu.addItem(redo)

        menu.addItem(.separator())

        let cut = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cut.target = nil
        menu.addItem(cut)

        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copy.target = nil
        menu.addItem(copy)

        let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        paste.target = nil
        menu.addItem(paste)

        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAll.target = nil
        menu.addItem(selectAll)

        menu.addItem(.separator())

        let copyID = NSMenuItem(title: "Copy My Tox ID", action: #selector(menuCopySelfID(_:)), keyEquivalent: "i")
        copyID.keyEquivalentModifierMask = [.command, .shift]
        copyID.target = self
        menu.addItem(copyID)

        return menu
    }

    private func buildPeersMenu() -> NSMenu {
        let menu = NSMenu(title: "Peers")

        let addPeer = NSMenuItem(title: "Add Peer…", action: #selector(menuOpenAddPeer(_:)), keyEquivalent: "n")
        addPeer.keyEquivalentModifierMask = [.command, .option]
        addPeer.target = self
        menu.addItem(addPeer)

        let copyID = NSMenuItem(title: "Copy My Tox ID", action: #selector(menuCopySelfID(_:)), keyEquivalent: "")
        copyID.target = self
        menu.addItem(copyID)

        return menu
    }

    private func buildGroupsMenu() -> NSMenu {
        let menu = NSMenu(title: "Groups")

        let host = NSMenuItem(title: "Host New Group…", action: #selector(menuHostGroup(_:)), keyEquivalent: "g")
        host.keyEquivalentModifierMask = [.command, .shift]
        host.target = self
        menu.addItem(host)

        let join = NSMenuItem(title: "Join Group…", action: #selector(menuJoinGroup(_:)), keyEquivalent: "j")
        join.keyEquivalentModifierMask = [.command, .shift]
        join.target = self
        menu.addItem(join)

        menu.addItem(.separator())

        let leave = NSMenuItem(title: "Leave Selected Group", action: #selector(menuLeaveSelectedGroup(_:)), keyEquivalent: "")
        leave.target = self
        menu.addItem(leave)

        return menu
    }

    private func buildWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")

        let minimize = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        minimize.target = nil
        menu.addItem(minimize)

        let zoom = NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        zoom.target = nil
        menu.addItem(zoom)

        return menu
    }

    @objc private func menuCopySelfID(_ sender: Any?) {
        viewModel.copySelfToxID()
    }

    @objc private func menuOpenAddPeer(_ sender: Any?) {
        viewModel.openAddFriendDialog()
    }

    @objc private func menuHostGroup(_ sender: Any?) {
        viewModel.openHostGroupDialog()
    }

    @objc private func menuJoinGroup(_ sender: Any?) {
        viewModel.openJoinGroupDialog()
    }

    @objc private func menuLeaveSelectedGroup(_ sender: Any?) {
        guard let selectedGroupID = viewModel.selectedGroupID,
              let group = viewModel.groupRooms.first(where: { $0.id == selectedGroupID }) else {
            NSSound.beep()
            return
        }

        viewModel.leaveGroup(group)
    }

    @objc private func menuOpenProfileSettings(_ sender: Any?) {
        viewModel.openProfileSettings()
    }

    @objc private func menuExportProfile(_ sender: Any?) {
        Task { @MainActor in
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

    @objc private func menuResetIdentity(_ sender: Any?) {
        viewModel.isResetConfirmationPresented = true
    }
}