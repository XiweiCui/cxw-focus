import AppKit
import FocusDockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: FocusDockController!
    private var dockPanelController: DockPanelController!
    private var desktopCurtainController: DesktopCurtainController!
    private var topStatusBarShieldController: TopStatusBarShieldController!
    private var menuBarController: MenuBarController!
    private var settingsWindowController: SettingsWindowController!
    private var ipcServer: IPCServer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let selfBundleID = Bundle.main.bundleIdentifier ?? WhitelistPolicy.defaultSelfBundleID
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existingInstances = NSRunningApplication.runningApplications(withBundleIdentifier: selfBundleID)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
        if let existing = existingInstances.first {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        controller = FocusDockController()
        dockPanelController = DockPanelController(controller: controller)
        desktopCurtainController = DesktopCurtainController(controller: controller)
        topStatusBarShieldController = TopStatusBarShieldController(controller: controller)
        menuBarController = MenuBarController(controller: controller)
        settingsWindowController = SettingsWindowController(controller: controller)

        controller.onOpenSettingsRequested = { [weak self] in
            self?.settingsWindowController.show()
        }

        menuBarController.onRequestOpenSettings = { [weak self] in
            self?.settingsWindowController.show()
        }

        menuBarController.onRequestOpenAddApp = { [weak self] in
            self?.controller.showFloatingDock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.dockPanelController.openAddAppPopover()
            }
        }

        if controller.isShowingDock {
            dockPanelController.show()
        }

        ipcServer = IPCServer { [weak controller] request in
            guard let controller else {
                return IPCResponse(ok: false, message: "Controller unavailable")
            }
            return controller.handleIPCRequest(request)
        }
        ipcServer.start()

        let isBackgroundLaunch = CommandLine.arguments.contains("--background")
        if !isBackgroundLaunch {
            controller.showFloatingDock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.menuBarController.showPopover()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showFloatingDock()
        if !controller.isInImmersiveMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.menuBarController.showPopover()
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktopCurtainController?.hide(animated: false)
        topStatusBarShieldController?.hide(animated: false)
        if let controller {
            if controller.isInImmersiveMode {
                controller.performExitImmersiveMode(synchronousDockRestore: true)
            } else {
                controller.systemDockController.restoreSystemDockIfNeeded(synchronous: true)
            }
        }
        ipcServer?.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            controller.handleURL(url)
        }
    }
}
