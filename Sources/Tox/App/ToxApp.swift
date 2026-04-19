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
}