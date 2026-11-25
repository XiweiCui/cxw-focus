import Foundation

public struct WindowSnapshot: Codable, Equatable, Sendable, Hashable {
    public var bundleID: String
    public var windowTitle: String
    public var windowIndex: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        bundleID: String,
        windowTitle: String,
        windowIndex: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.windowIndex = windowIndex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct FocusModeConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var symbolName: String
    public var accentHex: String
    public var presetAppBundleIDs: [String]
    public var shortcutOnEnter: String?
    public var windowLayout: [WindowSnapshot]

    public init(
        id: String,
        name: String,
        symbolName: String,
        accentHex: String,
        presetAppBundleIDs: [String],
        shortcutOnEnter: String? = nil,
        windowLayout: [WindowSnapshot] = []
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.presetAppBundleIDs = presetAppBundleIDs
        self.shortcutOnEnter = shortcutOnEnter
        self.windowLayout = windowLayout
    }
}

public struct MinimizedWindowInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var pid: Int32
    public var bundleID: String
    public var title: String
    public var windowIndex: Int

    public init(
        id: String,
        pid: Int32,
        bundleID: String,
        title: String,
        windowIndex: Int
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
        self.windowIndex = windowIndex
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultUtilityWhitelist = [
        "com.1password.1password",
        "com.quicksnap.menubar"
    ]

    public var autoHideSystemDock: Bool
    public var autoHideFloatingDockInImmersive: Bool
    public var hideFloatingDockWhenFree: Bool
    public var showBlockedToast: Bool
    public var hideDesktopItemsInImmersive: Bool
    public var hideMenuBarIconsInImmersive: Bool
    public var showMinimizedWindowsInDock: Bool
    public var shortcutOnExit: String?
    public var utilityWhitelistBundleIDs: [String]

    public init(
        autoHideSystemDock: Bool = true,
        autoHideFloatingDockInImmersive: Bool = false,
        hideFloatingDockWhenFree: Bool = true,
        showBlockedToast: Bool = true,
        hideDesktopItemsInImmersive: Bool = true,
        hideMenuBarIconsInImmersive: Bool = true,
        showMinimizedWindowsInDock: Bool = true,
        shortcutOnExit: String? = nil,
        utilityWhitelistBundleIDs: [String] = AppSettings.defaultUtilityWhitelist
    ) {
        self.autoHideSystemDock = autoHideSystemDock
        self.autoHideFloatingDockInImmersive = autoHideFloatingDockInImmersive
        self.hideFloatingDockWhenFree = hideFloatingDockWhenFree
        self.showBlockedToast = showBlockedToast
        self.hideDesktopItemsInImmersive = hideDesktopItemsInImmersive
        self.hideMenuBarIconsInImmersive = hideMenuBarIconsInImmersive
        self.showMinimizedWindowsInDock = showMinimizedWindowsInDock
        self.shortcutOnExit = shortcutOnExit
        self.utilityWhitelistBundleIDs = utilityWhitelistBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.autoHideSystemDock = try container.decodeIfPresent(Bool.self, forKey: .autoHideSystemDock) ?? true
        self.autoHideFloatingDockInImmersive = try container.decodeIfPresent(Bool.self, forKey: .autoHideFloatingDockInImmersive) ?? false
        self.hideFloatingDockWhenFree = try container.decodeIfPresent(Bool.self, forKey: .hideFloatingDockWhenFree) ?? true
        self.showBlockedToast = try container.decodeIfPresent(Bool.self, forKey: .showBlockedToast) ?? true
        self.hideDesktopItemsInImmersive = try container.decodeIfPresent(Bool.self, forKey: .hideDesktopItemsInImmersive) ?? true
        self.hideMenuBarIconsInImmersive = try container.decodeIfPresent(Bool.self, forKey: .hideMenuBarIconsInImmersive) ?? true
        self.showMinimizedWindowsInDock = try container.decodeIfPresent(Bool.self, forKey: .showMinimizedWindowsInDock) ?? true
        self.shortcutOnExit = try container.decodeIfPresent(String.self, forKey: .shortcutOnExit)
        self.utilityWhitelistBundleIDs = try container.decodeIfPresent([String].self, forKey: .utilityWhitelistBundleIDs) ?? Self.defaultUtilityWhitelist
    }
}

public struct FocusDockConfig: Codable, Equatable, Sendable {
    public var modes: [FocusModeConfig]
    public var settings: AppSettings

    public init(modes: [FocusModeConfig], settings: AppSettings = AppSettings()) {
        self.modes = modes
        self.settings = settings
    }
}

public enum IPCCommand: String, Codable, Sendable {
    case status
    case list
    case enter
    case exit
    case add
    case remove
    case saveLayout
}

public struct IPCRequest: Codable, Equatable, Sendable {
    public var command: IPCCommand
    public var target: String?
    public var force: Bool?

    public init(command: IPCCommand, target: String? = nil, force: Bool? = nil) {
        self.command = command
        self.target = target
        self.force = force
    }
}

public struct IPCModeSummary: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var symbolName: String
    public var accentHex: String
    public var presetAppBundleIDs: [String]
    public var savedWindowCount: Int

    public init(
        id: String,
        name: String,
        symbolName: String,
        accentHex: String,
        presetAppBundleIDs: [String],
        savedWindowCount: Int
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.presetAppBundleIDs = presetAppBundleIDs
        self.savedWindowCount = savedWindowCount
    }
}

public struct IPCStatusPayload: Codable, Equatable, Sendable {
    public var state: String // "free" or "immersive"
    public var activeModeID: String?
    public var activeModeName: String?
    public var elapsedSeconds: Int?
    public var presetAppBundleIDs: [String]
    public var temporaryAppBundleIDs: [String]
    public var autoHideSystemDock: Bool

    public init(
        state: String,
        activeModeID: String? = nil,
        activeModeName: String? = nil,
        elapsedSeconds: Int? = nil,
        presetAppBundleIDs: [String] = [],
        temporaryAppBundleIDs: [String] = [],
        autoHideSystemDock: Bool = true
    ) {
        self.state = state
        self.activeModeID = activeModeID
        self.activeModeName = activeModeName
        self.elapsedSeconds = elapsedSeconds
        self.presetAppBundleIDs = presetAppBundleIDs
        self.temporaryAppBundleIDs = temporaryAppBundleIDs
        self.autoHideSystemDock = autoHideSystemDock
    }
}

public struct IPCResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var message: String
    public var status: IPCStatusPayload?
    public var modes: [IPCModeSummary]?

    public init(
        ok: Bool,
        message: String,
        status: IPCStatusPayload? = nil,
        modes: [IPCModeSummary]? = nil
    ) {
        self.ok = ok
        self.message = message
        self.status = status
        self.modes = modes
    }
}
