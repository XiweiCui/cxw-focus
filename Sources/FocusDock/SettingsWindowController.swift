import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let controller: FocusDockController
    private var window: NSWindow?

    init(controller: FocusDockController) {
        self.controller = controller
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(controller: controller))
        let window = NSWindow(contentViewController: hosting)
        window.title = "CXW focus 偏好设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 640, height: 500))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
