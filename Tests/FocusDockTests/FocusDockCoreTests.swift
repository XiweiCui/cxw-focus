import XCTest
@testable import FocusDockCore

final class FocusDockCoreTests: XCTestCase {

    func testWhitelistFreeModeAllowsEverything() {
        let browsers = ["com.google.Chrome", "com.apple.Safari", "com.tencent.xinWeChat"]
        for bid in browsers {
            XCTAssertTrue(
                WhitelistPolicy.isAllowed(
                    bundleID: bid,
                    activeMode: nil,
                    temporaryBundleIDs: [],
                    utilityWhitelist: []
                )
            )
        }
    }

    func testWhitelistBlocksBrowsersAndUnlistedAppsInImmersiveMode() {
        let mode = FocusModeConfig(
            id: "coding",
            name: "开发",
            symbolName: "hammer.fill",
            accentHex: "#3B82F6",
            presetAppBundleIDs: ["com.google.antigravity", "com.apple.Terminal"]
        )

        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: "com.google.antigravity",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: ["com.1password.1password"]
        ))

        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: "com.1password.1password",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: ["com.1password.1password"]
        ))

        // Browsers and messaging apps must be blocked
        XCTAssertFalse(WhitelistPolicy.isAllowed(
            bundleID: "com.google.Chrome",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: ["com.1password.1password"]
        ))
        XCTAssertFalse(WhitelistPolicy.isAllowed(
            bundleID: "com.apple.Safari",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: []
        ))
        XCTAssertFalse(WhitelistPolicy.isAllowed(
            bundleID: "com.tencent.xinWeChat",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: []
        ))
    }

    func testWhitelistAllowsTemporaryAppsAndSystemEssentials() {
        let mode = FocusModeConfig(
            id: "writing",
            name: "写作",
            symbolName: "pencil.line",
            accentHex: "#D97706",
            presetAppBundleIDs: ["md.obsidian"]
        )

        // Temporary app allowed
        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: "com.apple.Preview",
            activeMode: mode,
            temporaryBundleIDs: ["com.apple.Preview"],
            utilityWhitelist: []
        ))

        // Self allowed
        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: WhitelistPolicy.defaultSelfBundleID,
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: []
        ))

        // System essentials, desktop anchor (Finder) & third-party input methods allowed
        XCTAssertTrue(WhitelistPolicy.isDesktopAnchor(bundleID: "com.apple.finder"))
        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: "com.apple.finder",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: []
        ))
        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: "com.apple.screencaptureui",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: []
        ))
        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: "com.apple.inputmethod.SCIM",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: []
        ))
        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: "com.tencent.inputmethod.wetype",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: []
        ))
        XCTAssertTrue(WhitelistPolicy.isAllowed(
            bundleID: "com.apple.appkit.xpc.openAndSavePanelService",
            activeMode: mode,
            temporaryBundleIDs: [],
            utilityWhitelist: []
        ))
    }

    func testCombinedDockBundleIDsDeduplicatesInOrder() {
        let mode = FocusModeConfig(
            id: "coding",
            name: "开发",
            symbolName: "hammer.fill",
            accentHex: "#3B82F6",
            presetAppBundleIDs: ["a.app", "b.app"]
        )
        let combined = WhitelistPolicy.combinedDockBundleIDs(
            for: mode,
            temporaryBundleIDs: ["b.app", "c.app", "c.app"]
        )
        XCTAssertEqual(combined, ["a.app", "b.app", "c.app"])
    }

    func testConfigStoreDefaultsExcludeBrowsersAndPersistRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusDockTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let mockInstalled: Set<String> = [
            "com.google.antigravity",
            "com.deepseek.dsh",
            "com.apple.Terminal",
            "md.obsidian",
            "com.apple.Notes",
            "com.1password.1password"
        ]
        let store = ConfigStore(fileURL: configURL) { mockInstalled.contains($0) }

        var loaded = store.load()
        XCTAssertEqual(loaded.modes.count, 3)
        XCTAssertEqual(loaded.modes.map(\.id), ["coding", "writing", "learning"])
        XCTAssertTrue(loaded.settings.autoHideSystemDock)
        XCTAssertTrue(loaded.settings.hideFloatingDockWhenFree)

        // Ensure no browser exists in any default mode
        let knownBrowsers = ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "company.thebrowser.Browser"]
        for mode in loaded.modes {
            for browser in knownBrowsers {
                XCTAssertFalse(mode.presetAppBundleIDs.contains(browser))
            }
        }

        // Modify & save round-trip
        loaded.modes[0].windowLayout = [
            WindowSnapshot(bundleID: "com.google.antigravity", windowTitle: "Workspace", windowIndex: 0, x: 10, y: 30, width: 1200, height: 800)
        ]
        loaded.modes[0].shortcutOnEnter = "工作专注"
        try store.save(loaded)

        let reloaded = store.load()
        XCTAssertEqual(reloaded, loaded)
    }

    func testIPCProtocolRoundTrip() throws {
        let req = IPCRequest(command: .enter, target: "coding", force: false)
        let reqData = try IPCProtocol.encodeLine(req)
        let decodedReq = try IPCProtocol.decodeRequest(from: reqData)
        XCTAssertEqual(decodedReq, req)

        let status = IPCStatusPayload(
            state: "immersive",
            activeModeID: "coding",
            activeModeName: "开发",
            elapsedSeconds: 42,
            presetAppBundleIDs: ["com.google.antigravity"],
            temporaryAppBundleIDs: ["com.apple.Preview"],
            autoHideSystemDock: true
        )
        let resp = IPCResponse(ok: true, message: "Entered coding", status: status)
        let respData = try IPCProtocol.encodeLine(resp)
        let decodedResp = try IPCProtocol.decodeResponse(from: respData)
        XCTAssertEqual(decodedResp, resp)
    }

    func testLegacyAppSettingsDecodingDefaultsNewImmersiveOptionsToTrue() throws {
        let legacyJSON = """
        {
          "autoHideSystemDock": true,
          "hideFloatingDockWhenFree": false,
          "showBlockedToast": true,
          "utilityWhitelistBundleIDs": ["com.1password.1password"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertTrue(decoded.autoHideSystemDock)
        XCTAssertFalse(decoded.autoHideFloatingDockInImmersive)
        XCTAssertFalse(decoded.hideFloatingDockWhenFree)
        XCTAssertTrue(decoded.showBlockedToast)
        XCTAssertTrue(decoded.hideDesktopItemsInImmersive)
        XCTAssertTrue(decoded.hideMenuBarIconsInImmersive)
        XCTAssertTrue(decoded.showMinimizedWindowsInDock)
        XCTAssertEqual(decoded.utilityWhitelistBundleIDs, ["com.1password.1password"])

        var updated = decoded
        updated.autoHideFloatingDockInImmersive = true
        let encoded = try JSONEncoder().encode(updated)
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertTrue(roundTrip.autoHideFloatingDockInImmersive)
    }
}
