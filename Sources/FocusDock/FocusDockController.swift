import AppKit
import Combine
import FocusDockCore
import Foundation

@MainActor
final class FocusDockController: ObservableObject {
    @Published var config: FocusDockConfig
    @Published var activeModeID: String?
    @Published var sessionStartDate: Date?
    @Published var temporaryBundleIDs: [String] = []
    @Published var runningBundleIDs: Set<String> = []
    @Published var frontmostBundleID: String?
    @Published var blockedToastMessage: String?
    @Published var isShowingDock: Bool = false
    @Published var availableShortcuts: [String] = []
    @Published var minimizedWindows: [MinimizedWindowInfo] = []

    let configStore: ConfigStore
    let appCatalog = AppCatalog()
    let systemDockController = SystemDockController()
    let windowLayoutManager = WindowLayoutManager()
    let notificationFocusController = NotificationFocusController()

    private(set) lazy var enforcer = FocusEnforcer(controller: self)
    private var toastDismissWorkItem: DispatchWorkItem?
    private var minimizedRefreshTimer: Timer?
    private var modeTransitionToken: Int = 0

    var onDockVisibilityChanged: ((Bool) -> Void)?
    var onOpenSettingsRequested: (() -> Void)?

    var activeMode: FocusModeConfig? {
        guard let activeModeID else { return nil }
        return config.modes.first(where: { $0.id == activeModeID })
    }

    var isInImmersiveMode: Bool {
        activeMode != nil
    }

    init(configStore: ConfigStore = ConfigStore()) {
        self.configStore = configStore
        self.config = configStore.load()
        self.isShowingDock = !config.settings.hideFloatingDockWhenFree
        // Undo any leftover Dock hide if a previous run ended unexpectedly
        systemDockController.recoverIfNeededOnLaunch()
        refreshRunningState()
        _ = enforcer
        refreshAvailableShortcuts()
    }

    func refreshRunningState() {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        runningBundleIDs = Set(running.compactMap(\.bundleIdentifier))
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func refreshAvailableShortcuts() {
        Task {
            let list = await notificationFocusController.listAvailableShortcuts()
            self.availableShortcuts = list
        }
    }

    // MARK: - Mode Transitions

    func enterMode(idOrName: String) {
        guard let mode = findMode(idOrName: idOrName) else { return }
        enterMode(id: mode.id)
    }

    func enterMode(id: String) {
        guard let mode = config.modes.first(where: { $0.id == id }) else { return }

        modeTransitionToken += 1
        let token = modeTransitionToken
        let wasFree = (activeModeID == nil)

        // Reset temporary apps when switching modes or starting a new session
        temporaryBundleIDs = []
        activeModeID = mode.id
        if wasFree || sessionStartDate == nil {
            sessionStartDate = Date()
        }

        showFloatingDock()

        if config.settings.autoHideSystemDock {
            systemDockController.hideSystemDockForImmersiveSession()
        }

        // Trigger notification focus shortcut asynchronously
        notificationFocusController.runShortcut(named: mode.shortcutOnEnter)

        // Defer window activation, hiding, and AX IPC slightly off the entrance frame
        // so the Dock slide-up, desktop curtain fade, and top bar fade begin at 120Hz immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, self.modeTransitionToken == token else { return }

            let runningPresetApps = NSWorkspace.shared.runningApplications.filter { app in
                guard let bid = app.bundleIdentifier, app.activationPolicy == .regular else { return false }
                return mode.presetAppBundleIDs.contains(bid)
            }
            for app in runningPresetApps where app.isHidden {
                app.unhide()
            }

            let selfBundleID = Bundle.main.bundleIdentifier ?? WhitelistPolicy.defaultSelfBundleID
            let currentFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let currentIsWorkspaceApp = currentFrontmost.map { bid in
                bid != selfBundleID &&
                !WhitelistPolicy.isDesktopAnchor(bundleID: bid) &&
                WhitelistPolicy.isAllowed(
                    bundleID: bid,
                    activeMode: mode,
                    temporaryBundleIDs: self.temporaryBundleIDs,
                    utilityWhitelist: self.config.settings.utilityWhitelistBundleIDs,
                    selfBundleID: selfBundleID
                )
            } ?? false

            if !currentIsWorkspaceApp {
                if let firstRunning = mode.presetAppBundleIDs.compactMap({ bid in
                    runningPresetApps.first(where: { $0.bundleIdentifier == bid })
                }).first {
                    self.enforcer.setLastAllowedBundleID(firstRunning.bundleIdentifier)
                    firstRunning.activate(options: [])
                } else if let firstPreset = mode.presetAppBundleIDs.first {
                    self.activateOrLaunchApp(bundleID: firstPreset)
                }
            } else {
                self.enforcer.setLastAllowedBundleID(currentFrontmost)
            }

            self.enforcer.hideAllDisallowedApps(for: mode, controller: self)
            self.refreshRunningState()
        }

        if !mode.windowLayout.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.modeTransitionToken == token else { return }
                self.windowLayoutManager.applyLayout(mode.windowLayout)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, self.modeTransitionToken == token else { return }
            self.refreshMinimizedWindows()
            self.startMinimizedRefreshTimer()
        }
    }

    func requestExitImmersiveMode(skipConfirmation: Bool = false) {
        guard isInImmersiveMode else { return }

        if skipConfirmation {
            performExitImmersiveMode()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "确定要退出沉浸模式吗？"
        alert.informativeText = "退出后将恢复系统原生程序坞、通知状态，并清空本次临时加入的软件。"
        alert.addButton(withTitle: "退出沉浸")
        alert.addButton(withTitle: "继续专注")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            performExitImmersiveMode()
        }
    }

    func performExitImmersiveMode(synchronousDockRestore: Bool = false) {
        modeTransitionToken += 1
        stopMinimizedRefreshTimer()
        minimizedWindows = []
        activeModeID = nil
        sessionStartDate = nil
        temporaryBundleIDs = []
        blockedToastMessage = nil

        systemDockController.restoreSystemDockIfNeeded(synchronous: synchronousDockRestore)
        notificationFocusController.runShortcut(named: config.settings.shortcutOnExit)

        if config.settings.hideFloatingDockWhenFree {
            hideFloatingDock()
        }
    }

    func startMinimizedRefreshTimer() {
        stopMinimizedRefreshTimer()
        guard isInImmersiveMode, config.settings.showMinimizedWindowsInDock else { return }
        minimizedRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMinimizedWindows()
            }
        }
    }

    func stopMinimizedRefreshTimer() {
        minimizedRefreshTimer?.invalidate()
        minimizedRefreshTimer = nil
    }

    func refreshMinimizedWindows() {
        guard let activeMode, config.settings.showMinimizedWindowsInDock else {
            if !minimizedWindows.isEmpty {
                minimizedWindows = []
            }
            return
        }
        let targetBundleIDs = WhitelistPolicy.combinedDockBundleIDs(
            for: activeMode,
            temporaryBundleIDs: temporaryBundleIDs
        )
        let latest = windowLayoutManager.listMinimizedWindows(for: targetBundleIDs)
        if latest != minimizedWindows {
            minimizedWindows = latest
        }
    }

    func restoreMinimizedWindow(_ info: MinimizedWindowInfo) {
        windowLayoutManager.restoreMinimizedWindow(info)
        enforcer.setLastAllowedBundleID(info.bundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshMinimizedWindows()
        }
    }

    func toggleDockVisibility() {
        if isShowingDock {
            hideFloatingDock()
        } else {
            showFloatingDock()
        }
    }

    func showFloatingDock() {
        isShowingDock = true
        onDockVisibilityChanged?(true)
    }

    func hideFloatingDock() {
        isShowingDock = false
        onDockVisibilityChanged?(false)
    }

    // MARK: - App Launching & Temporary Slots

    func activateOrLaunchApp(bundleID: String) {
        if let minimized = minimizedWindows.first(where: { $0.bundleID == bundleID }) {
            restoreMinimizedWindow(minimized)
            return
        }

        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }) {
            running.unhide()
            if let appURL = running.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let openConfig = NSWorkspace.OpenConfiguration()
                openConfig.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: openConfig) { [weak self] _, _ in
                    Task { @MainActor in
                        self?.enforcer.setLastAllowedBundleID(bundleID)
                        self?.refreshRunningState()
                        self?.refreshMinimizedWindows()
                    }
                }
            } else {
                running.activate(options: [])
                enforcer.setLastAllowedBundleID(bundleID)
            }
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        let openConfig = NSWorkspace.OpenConfiguration()
        openConfig.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: openConfig) { [weak self] _, _ in
            Task { @MainActor in
                self?.enforcer.setLastAllowedBundleID(bundleID)
                self?.refreshRunningState()
                self?.refreshMinimizedWindows()
            }
        }
    }

    func addTemporaryApp(bundleID: String) {
        guard let activeMode else { return }
        if activeMode.presetAppBundleIDs.contains(bundleID) || temporaryBundleIDs.contains(bundleID) {
            return
        }
        temporaryBundleIDs.append(bundleID)
        activateOrLaunchApp(bundleID: bundleID)
    }

    func removeTemporaryApp(bundleID: String) {
        temporaryBundleIDs.removeAll { $0 == bundleID }
        if let activeMode,
           !WhitelistPolicy.isAllowed(
               bundleID: bundleID,
               activeMode: activeMode,
               temporaryBundleIDs: temporaryBundleIDs,
               utilityWhitelist: config.settings.utilityWhitelistBundleIDs
           ),
           let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            running.hide()
        }
    }

    func promoteTemporaryAppToPreset(bundleID: String) {
        guard let activeModeID,
              let idx = config.modes.firstIndex(where: { $0.id == activeModeID }) else {
            return
        }
        if !config.modes[idx].presetAppBundleIDs.contains(bundleID) {
            config.modes[idx].presetAppBundleIDs.append(bundleID)
            saveConfig()
        }
        temporaryBundleIDs.removeAll { $0 == bundleID }
    }

    func addPresetApp(bundleID: String, to modeID: String) {
        guard let idx = config.modes.firstIndex(where: { $0.id == modeID }) else { return }
        if !config.modes[idx].presetAppBundleIDs.contains(bundleID) {
            config.modes[idx].presetAppBundleIDs.append(bundleID)
            saveConfig()
        }
        temporaryBundleIDs.removeAll { $0 == bundleID }
    }

    func removePresetApp(bundleID: String, from modeID: String) {
        guard let idx = config.modes.firstIndex(where: { $0.id == modeID }) else { return }
        config.modes[idx].presetAppBundleIDs.removeAll { $0 == bundleID }
        saveConfig()
    }

    // MARK: - Window Layouts

    @discardableResult
    func saveCurrentWindowLayout(for modeID: String? = nil) -> Int {
        let targetID = modeID ?? activeModeID
        guard let targetID,
              let idx = config.modes.firstIndex(where: { $0.id == targetID }) else {
            return 0
        }

        if !WindowLayoutManager.isAccessibilityTrusted() {
            WindowLayoutManager.requestAccessibilityPermission()
            showToast("请先在系统设置中授予「辅助功能」权限")
            return 0
        }

        let targetBundles = WhitelistPolicy.combinedDockBundleIDs(
            for: config.modes[idx],
            temporaryBundleIDs: (targetID == activeModeID ? temporaryBundleIDs : [])
        )
        let snapshots = windowLayoutManager.captureLayout(for: targetBundles)
        config.modes[idx].windowLayout = snapshots
        saveConfig()
        showToast(snapshots.isEmpty ? "未检测到可保存的窗口" : "已记住 \(snapshots.count) 个窗口布局")
        return snapshots.count
    }

    func clearWindowLayout(for modeID: String) {
        guard let idx = config.modes.firstIndex(where: { $0.id == modeID }) else { return }
        config.modes[idx].windowLayout = []
        saveConfig()
    }

    // MARK: - Mode & Settings CRUD

    @discardableResult
    func addMode(name: String = "新档位", symbolName: String = "sparkles", accentHex: String = "#8B5CF6") -> FocusModeConfig {
        let mode = FocusModeConfig(
            id: "mode-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            symbolName: symbolName,
            accentHex: accentHex,
            presetAppBundleIDs: []
        )
        config.modes.append(mode)
        saveConfig()
        return mode
    }

    func updateMode(_ mode: FocusModeConfig) {
        guard let idx = config.modes.firstIndex(where: { $0.id == mode.id }) else { return }
        config.modes[idx] = mode
        saveConfig()
    }

    func deleteMode(id: String) {
        if activeModeID == id {
            performExitImmersiveMode()
        }
        config.modes.removeAll { $0.id == id }
        saveConfig()
    }

    func saveConfig() {
        try? configStore.save(config)
    }

    // MARK: - Toast Notification

    func notifyBlockedApp(named appName: String) {
        guard config.settings.showBlockedToast else { return }
        showToast("已拦截「\(appName)」· 当前处于沉浸模式")
    }

    func showToast(_ message: String) {
        toastDismissWorkItem?.cancel()
        blockedToastMessage = message
        let item = DispatchWorkItem { [weak self] in
            self?.blockedToastMessage = nil
        }
        toastDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: item)
    }

    // MARK: - Helpers

    func findMode(idOrName: String) -> FocusModeConfig? {
        let trimmed = idOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let byID = config.modes.first(where: { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return byID
        }
        return config.modes.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
    }

    // MARK: - IPC & URL Handling

    func makeStatusPayload() -> IPCStatusPayload {
        let elapsed: Int? = sessionStartDate.map { max(0, Int(Date().timeIntervalSince($0))) }
        return IPCStatusPayload(
            state: isInImmersiveMode ? "immersive" : "free",
            activeModeID: activeMode?.id,
            activeModeName: activeMode?.name,
            elapsedSeconds: elapsed,
            presetAppBundleIDs: activeMode?.presetAppBundleIDs ?? [],
            temporaryAppBundleIDs: temporaryBundleIDs,
            autoHideSystemDock: config.settings.autoHideSystemDock
        )
    }

    func handleIPCRequest(_ request: IPCRequest) -> IPCResponse {
        switch request.command {
        case .status:
            return IPCResponse(
                ok: true,
                message: isInImmersiveMode ? "Immersive mode: \(activeMode?.name ?? "")" : "Free mode",
                status: makeStatusPayload()
            )

        case .list:
            let summaries = config.modes.map { mode in
                IPCModeSummary(
                    id: mode.id,
                    name: mode.name,
                    symbolName: mode.symbolName,
                    accentHex: mode.accentHex,
                    presetAppBundleIDs: mode.presetAppBundleIDs,
                    savedWindowCount: mode.windowLayout.count
                )
            }
            return IPCResponse(ok: true, message: "OK", status: makeStatusPayload(), modes: summaries)

        case .enter:
            guard let target = request.target, let mode = findMode(idOrName: target) else {
                return IPCResponse(ok: false, message: "Mode not found: \(request.target ?? "")", status: makeStatusPayload())
            }
            enterMode(id: mode.id)
            return IPCResponse(ok: true, message: "Entered \(mode.name) (\(mode.id))", status: makeStatusPayload())

        case .exit:
            guard isInImmersiveMode else {
                return IPCResponse(ok: true, message: "Already in free mode", status: makeStatusPayload())
            }
            if request.force == true {
                performExitImmersiveMode()
                return IPCResponse(ok: true, message: "Exited immersive mode", status: makeStatusPayload())
            } else {
                // Schedule non-blocking modal confirmation on next runloop turn
                DispatchQueue.main.async { [weak self] in
                    self?.requestExitImmersiveMode(skipConfirmation: false)
                }
                return IPCResponse(ok: true, message: "Requested exit confirmation dialog", status: makeStatusPayload())
            }

        case .add:
            guard isInImmersiveMode else {
                return IPCResponse(ok: false, message: "Not in immersive mode; enter a mode first", status: makeStatusPayload())
            }
            guard let target = request.target,
                  let resolvedBundleID = appCatalog.resolveBundleID(fromQuery: target) else {
                return IPCResponse(ok: false, message: "App not found: \(request.target ?? "")", status: makeStatusPayload())
            }
            addTemporaryApp(bundleID: resolvedBundleID)
            return IPCResponse(ok: true, message: "Added \(resolvedBundleID) to temporary slots", status: makeStatusPayload())

        case .remove:
            guard isInImmersiveMode else {
                return IPCResponse(ok: false, message: "Not in immersive mode", status: makeStatusPayload())
            }
            guard let target = request.target,
                  let resolvedBundleID = appCatalog.resolveBundleID(fromQuery: target) else {
                return IPCResponse(ok: false, message: "App not found: \(request.target ?? "")", status: makeStatusPayload())
            }
            removeTemporaryApp(bundleID: resolvedBundleID)
            return IPCResponse(ok: true, message: "Removed \(resolvedBundleID) from temporary slots", status: makeStatusPayload())

        case .saveLayout:
            guard isInImmersiveMode else {
                return IPCResponse(ok: false, message: "Not in immersive mode", status: makeStatusPayload())
            }
            let count = saveCurrentWindowLayout()
            return IPCResponse(ok: true, message: "Saved \(count) window frames", status: makeStatusPayload())
        }
    }

    func handleURL(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        guard scheme == "cxwfocus" || scheme == "focusdock" else { return }
        let action = url.host?.lowercased() ?? ""
        let pathArg = url.pathComponents.dropFirst().joined(separator: "/")

        switch action {
        case "enter":
            if !pathArg.isEmpty {
                enterMode(idOrName: pathArg)
            }
        case "exit":
            requestExitImmersiveMode(skipConfirmation: false)
        case "add":
            if !pathArg.isEmpty, let bid = appCatalog.resolveBundleID(fromQuery: pathArg) {
                addTemporaryApp(bundleID: bid)
            }
        case "settings":
            onOpenSettingsRequested?()
        default:
            break
        }
    }
}
