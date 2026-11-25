import AppKit
import Foundation

public enum FocusDockPaths {
    public static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("CXWFocus", isDirectory: true)
    }

    public static func legacyAppSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("FocusDock", isDirectory: true)
    }

    public static func defaultConfigURL() -> URL {
        appSupportDirectory().appendingPathComponent("config.json", isDirectory: false)
    }

    public static func socketURL() -> URL {
        appSupportDirectory().appendingPathComponent("ipc.sock", isDirectory: false)
    }
}

public final class ConfigStore {
    public let fileURL: URL
    private let appAvailabilityChecker: (String) -> Bool

    public init(
        fileURL: URL = FocusDockPaths.defaultConfigURL(),
        appAvailabilityChecker: @escaping (String) -> Bool = ConfigStore.defaultAppAvailabilityChecker
    ) {
        self.fileURL = fileURL
        self.appAvailabilityChecker = appAvailabilityChecker
    }

    public static func defaultAppAvailabilityChecker(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    public func load() -> FocusDockConfig {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path),
           fileURL == FocusDockPaths.defaultConfigURL() {
            let legacyURL = FocusDockPaths.legacyAppSupportDirectory().appendingPathComponent("config.json", isDirectory: false)
            if fm.fileExists(atPath: legacyURL.path) {
                try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: legacyURL, to: fileURL)
            }
        }
        if fm.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                return try decoder.decode(FocusDockConfig.self, from: data)
            } catch {
                // If corrupted, back up and recreate clean defaults
                let backupURL = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
                try? fm.removeItem(at: backupURL)
                try? fm.moveItem(at: fileURL, to: backupURL)
            }
        }
        let defaults = makeDefaultConfig(filterInstalled: true)
        try? save(defaults)
        return defaults
    }

    public func save(_ config: FocusDockConfig) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    public func makeDefaultConfig(filterInstalled: Bool = true) -> FocusDockConfig {
        func resolveApps(_ candidates: [String]) -> [String] {
            guard filterInstalled else { return candidates }
            let installed = candidates.filter { appAvailabilityChecker($0) }
            return installed.isEmpty ? candidates : installed
        }

        let codingApps = resolveApps([
            "com.google.antigravity",
            "com.deepseek.dsh",
            "com.microsoft.VSCode",
            "com.apple.Terminal",
            "com.anthropic.claudefordesktop"
        ])

        let writingApps = resolveApps([
            "md.obsidian",
            "com.quoteunquoteapps.highland.pro",
            "com.apple.Notes",
            "com.google.antigravity"
        ])

        let learningApps = resolveApps([
            "md.obsidian",
            "com.apple.Preview",
            "com.apple.Notes",
            "com.anthropic.claudefordesktop"
        ])

        let utilityApps = filterInstalled
            ? ["com.1password.1password", "com.quicksnap.menubar"].filter { appAvailabilityChecker($0) }
            : ["com.1password.1password", "com.quicksnap.menubar"]

        let modes = [
            FocusModeConfig(
                id: "coding",
                name: "开发",
                symbolName: "hammer.fill",
                accentHex: "#3B82F6",
                presetAppBundleIDs: codingApps
            ),
            FocusModeConfig(
                id: "writing",
                name: "写作",
                symbolName: "pencil.line",
                accentHex: "#D97706",
                presetAppBundleIDs: writingApps
            ),
            FocusModeConfig(
                id: "learning",
                name: "学习",
                symbolName: "book.fill",
                accentHex: "#10B981",
                presetAppBundleIDs: learningApps
            )
        ]

        let settings = AppSettings(
            autoHideSystemDock: true,
            hideFloatingDockWhenFree: true,
            showBlockedToast: true,
            shortcutOnExit: nil,
            utilityWhitelistBundleIDs: utilityApps
        )

        return FocusDockConfig(modes: modes, settings: settings)
    }
}
