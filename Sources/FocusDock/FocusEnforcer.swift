import AppKit
import FocusDockCore
import Foundation

@MainActor
final class FocusEnforcer {
    private weak var controller: FocusDockController?
    private var observers: [NSObjectProtocol] = []
    private var lastBlockedByPID: [pid_t: Date] = [:]
    private var isEnforcing = false
    private(set) var lastAllowedBundleID: String?

    init(controller: FocusDockController) {
        self.controller = controller
        installObservers()
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for observer in observers {
            nc.removeObserver(observer)
        }
    }

    func setLastAllowedBundleID(_ bundleID: String?) {
        lastAllowedBundleID = bundleID
    }

    private func installObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        let activateObs = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                self?.handleActivation(app)
            }
        }
        observers.append(activateObs)

        let launchObs = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                self?.controller?.refreshRunningState()
                self?.handleActivation(app)
            }
        }
        observers.append(launchObs)

        for name in [
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ] {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.controller?.refreshRunningState()
                }
            }
            observers.append(obs)
        }
    }

    private func handleActivation(_ app: NSRunningApplication?) {
        guard let controller else { return }
        controller.refreshRunningState()

        // Ignore accessory/background apps (e.g. QuickSnap, input methods, menu bar tools)
        guard let app,
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier else {
            return
        }

        // In Free Mode, track the frontmost app unless it's Finder desktop anchor
        guard let activeMode = controller.activeMode else {
            if !WhitelistPolicy.isDesktopAnchor(bundleID: bundleID) {
                lastAllowedBundleID = bundleID
            }
            return
        }

        // Never block Finder (desktop anchor) so macOS always has a stable fallback target
        // when 0 whitelisted apps are running, preventing Space-switching / flicker loops.
        if WhitelistPolicy.isDesktopAnchor(bundleID: bundleID) {
            return
        }

        let selfBundleID = Bundle.main.bundleIdentifier ?? WhitelistPolicy.defaultSelfBundleID
        let allowed = WhitelistPolicy.isAllowed(
            bundleID: bundleID,
            activeMode: activeMode,
            temporaryBundleIDs: controller.temporaryBundleIDs,
            utilityWhitelist: controller.config.settings.utilityWhitelistBundleIDs,
            selfBundleID: selfBundleID
        )

        if allowed {
            if bundleID != selfBundleID && !WhitelistPolicy.isSystemEssential(bundleID: bundleID) {
                lastAllowedBundleID = bundleID
            }
            return
        }

        // Re-entrancy guard & per-PID cooldown to eliminate focus ping-pong loops
        guard !isEnforcing else { return }
        let now = Date()
        if let lastTime = lastBlockedByPID[app.processIdentifier],
           now.timeIntervalSince(lastTime) < 0.8 {
            return
        }

        isEnforcing = true
        lastBlockedByPID[app.processIdentifier] = now
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.isEnforcing = false
        }

        // Restore focus to a valid target BEFORE hiding the disallowed app so macOS
        // doesn't fall back to another hidden/background app across Spaces.
        let fallbackTarget = findFallbackAllowedApp(for: activeMode, controller: controller)
        if let fallbackTarget {
            fallbackTarget.unhide()
            fallbackTarget.activate(options: [])
        } else if let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == WhitelistPolicy.finderBundleID && !$0.isTerminated
        }) {
            finder.activate(options: [])
        }

        app.hide()

        let appName = app.localizedName ?? controller.appCatalog.entry(for: bundleID).name
        controller.notifyBlockedApp(named: appName)
    }

    func hideAllDisallowedApps(for activeMode: FocusModeConfig, controller: FocusDockController) {
        let selfBundleID = Bundle.main.bundleIdentifier ?? WhitelistPolicy.defaultSelfBundleID
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            if WhitelistPolicy.isDesktopAnchor(bundleID: bundleID) {
                continue
            }
            let allowed = WhitelistPolicy.isAllowed(
                bundleID: bundleID,
                activeMode: activeMode,
                temporaryBundleIDs: controller.temporaryBundleIDs,
                utilityWhitelist: controller.config.settings.utilityWhitelistBundleIDs,
                selfBundleID: selfBundleID
            )
            if !allowed && !app.isHidden {
                app.hide()
            }
        }
    }

    private func findFallbackAllowedApp(
        for activeMode: FocusModeConfig,
        controller: FocusDockController
    ) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }

        if let lastAllowedBundleID,
           !WhitelistPolicy.isDesktopAnchor(bundleID: lastAllowedBundleID),
           WhitelistPolicy.isAllowed(
               bundleID: lastAllowedBundleID,
               activeMode: activeMode,
               temporaryBundleIDs: controller.temporaryBundleIDs,
               utilityWhitelist: controller.config.settings.utilityWhitelistBundleIDs
           ),
           let app = running.first(where: { $0.bundleIdentifier == lastAllowedBundleID }) {
            return app
        }

        let combined = WhitelistPolicy.combinedDockBundleIDs(
            for: activeMode,
            temporaryBundleIDs: controller.temporaryBundleIDs
        )
        for bid in combined {
            if let app = running.first(where: { $0.bundleIdentifier == bid }) {
                lastAllowedBundleID = bid
                return app
            }
        }
        return nil
    }
}
