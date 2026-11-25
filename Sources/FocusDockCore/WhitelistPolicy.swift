import Foundation

public enum WhitelistPolicy {
    public static let defaultSelfBundleID = "com.cxw.focus"
    public static let legacySelfBundleID = "com.focusdock.app"
    public static let finderBundleID = "com.apple.finder"

    public static let systemEssentialBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.universalaccessAuthWarn",
        "com.apple.UserNotificationCenter",
        "com.apple.screencaptureui",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.CoreServicesUIAgent",
        "com.apple.coreservices.uiagent",
        "com.apple.authorizationhost",
        "com.apple.PressAndHold",
        "com.apple.TextInputMenuAgent",
        "com.apple.TextInputSwitcher",
        "com.apple.Spotlight",
        "com.apple.appkit.xpc.openAndSavePanelService"
    ]

    public static let systemEssentialPrefixes: [String] = [
        "com.apple.inputmethod.",
        "com.apple.TextInput",
        "com.apple.security.",
        "com.apple.appkit.xpc."
    ]

    public static func isSystemEssential(bundleID: String) -> Bool {
        if systemEssentialBundleIDs.contains(bundleID) {
            return true
        }
        if bundleID.contains(".inputmethod.") {
            return true
        }
        return systemEssentialPrefixes.contains { bundleID.hasPrefix($0) }
    }

    public static func isDesktopAnchor(bundleID: String) -> Bool {
        bundleID == finderBundleID
    }

    public static func isAllowed(
        bundleID: String,
        activeMode: FocusModeConfig?,
        temporaryBundleIDs: [String],
        utilityWhitelist: [String],
        selfBundleID: String = defaultSelfBundleID
    ) -> Bool {
        guard let activeMode else {
            return true
        }
        if bundleID == selfBundleID || bundleID == legacySelfBundleID {
            return true
        }
        if isSystemEssential(bundleID: bundleID) || isDesktopAnchor(bundleID: bundleID) {
            return true
        }
        if activeMode.presetAppBundleIDs.contains(bundleID) {
            return true
        }
        if temporaryBundleIDs.contains(bundleID) {
            return true
        }
        if utilityWhitelist.contains(bundleID) {
            return true
        }
        return false
    }

    public static func combinedDockBundleIDs(
        for mode: FocusModeConfig,
        temporaryBundleIDs: [String]
    ) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for bid in mode.presetAppBundleIDs + temporaryBundleIDs {
            if seen.insert(bid).inserted {
                result.append(bid)
            }
        }
        return result
    }
}
