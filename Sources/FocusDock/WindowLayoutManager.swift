import AppKit
import ApplicationServices
import FocusDockCore
import Foundation

@MainActor
final class WindowLayoutManager {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func captureLayout(for bundleIDs: [String]) -> [WindowSnapshot] {
        guard Self.isAccessibilityTrusted() else {
            return []
        }

        let targetSet = Set(bundleIDs)
        var snapshots: [WindowSnapshot] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, targetSet.contains(bid) else {
                continue
            }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows = standardWindows(of: appElement)
            for (idx, window) in windows.enumerated() {
                guard let pos = readPointAttribute(window, attribute: kAXPositionAttribute as CFString),
                      let size = readSizeAttribute(window, attribute: kAXSizeAttribute as CFString) else {
                    continue
                }
                let title = readStringAttribute(window, attribute: kAXTitleAttribute as CFString) ?? ""
                snapshots.append(
                    WindowSnapshot(
                        bundleID: bid,
                        windowTitle: title,
                        windowIndex: idx,
                        x: Double(pos.x),
                        y: Double(pos.y),
                        width: Double(size.width),
                        height: Double(size.height)
                    )
                )
            }
        }
        return snapshots
    }

    func applyLayout(_ snapshots: [WindowSnapshot]) {
        guard !snapshots.isEmpty, Self.isAccessibilityTrusted() else {
            return
        }

        let grouped = Dictionary(grouping: snapshots, by: \.bundleID)
        for (bundleID, appSnapshots) in grouped {
            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular
            }) else {
                continue
            }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows = standardWindows(of: appElement)
            guard !windows.isEmpty else { continue }

            var usedWindowIndices: Set<Int> = []
            for snapshot in appSnapshots.sorted(by: { $0.windowIndex < $1.windowIndex }) {
                guard let targetWindowIndex = matchWindowIndex(for: snapshot, in: windows, used: usedWindowIndices) else {
                    continue
                }
                usedWindowIndices.insert(targetWindowIndex)
                let window = windows[targetWindowIndex]

                // Unminimize if minimized
                if let minimized = readBoolAttribute(window, attribute: kAXMinimizedAttribute as CFString), minimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }

                var size = CGSize(width: snapshot.width, height: snapshot.height)
                var point = CGPoint(x: snapshot.x, y: snapshot.y)

                if let sizeVal = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
                }
                if let posVal = AXValueCreate(.cgPoint, &point) {
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
                }
                if let sizeVal = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
                }
            }
        }
    }

    func listMinimizedWindows(for bundleIDs: [String]) -> [MinimizedWindowInfo] {
        guard Self.isAccessibilityTrusted() else {
            return []
        }

        let targetSet = Set(bundleIDs)
        var result: [MinimizedWindowInfo] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            guard let bid = app.bundleIdentifier, targetSet.contains(bid) else {
                continue
            }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows = standardWindows(of: appElement)
            for (idx, window) in windows.enumerated() {
                let isMinimized = readBoolAttribute(window, attribute: kAXMinimizedAttribute as CFString) ?? false
                guard isMinimized else { continue }
                let rawTitle = readStringAttribute(window, attribute: kAXTitleAttribute as CFString)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let displayTitle = rawTitle.isEmpty ? (app.localizedName ?? bid) : rawTitle
                result.append(
                    MinimizedWindowInfo(
                        id: "\(app.processIdentifier):\(idx):\(displayTitle)",
                        pid: app.processIdentifier,
                        bundleID: bid,
                        title: displayTitle,
                        windowIndex: idx
                    )
                )
            }
        }
        return result
    }

    func restoreMinimizedWindow(_ info: MinimizedWindowInfo) {
        guard Self.isAccessibilityTrusted() else { return }

        let targetApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier == info.pid && !$0.isTerminated
        }) ?? NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == info.bundleID && $0.activationPolicy == .regular && !$0.isTerminated
        })

        guard let app = targetApp else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = standardWindows(of: appElement)
        guard !windows.isEmpty else { return }

        let targetWindow: AXUIElement? = windows.first(where: { win in
            let isMin = readBoolAttribute(win, attribute: kAXMinimizedAttribute as CFString) ?? false
            let title = readStringAttribute(win, attribute: kAXTitleAttribute as CFString)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return isMin && title == info.title
        }) ?? (info.windowIndex >= 0 && info.windowIndex < windows.count ? windows[info.windowIndex] : nil)
            ?? windows.first(where: { readBoolAttribute($0, attribute: kAXMinimizedAttribute as CFString) == true })

        if let targetWindow {
            AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        }
        if app.isHidden {
            app.unhide()
        }
        app.activate(options: [])
    }

    private func matchWindowIndex(
        for snapshot: WindowSnapshot,
        in windows: [AXUIElement],
        used: Set<Int>
    ) -> Int? {
        if !snapshot.windowTitle.isEmpty {
            if let exact = windows.indices.first(where: { idx in
                !used.contains(idx) && readStringAttribute(windows[idx], attribute: kAXTitleAttribute as CFString) == snapshot.windowTitle
            }) {
                return exact
            }
        }
        if snapshot.windowIndex >= 0 && snapshot.windowIndex < windows.count && !used.contains(snapshot.windowIndex) {
            return snapshot.windowIndex
        }
        return windows.indices.first(where: { !used.contains($0) })
    }

    private func standardWindows(of appElement: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let list = value as? [AXUIElement] else {
            return []
        }
        return list.filter { window in
            guard let subrole = readStringAttribute(window, attribute: kAXSubroleAttribute as CFString) else {
                return true
            }
            return subrole == (kAXStandardWindowSubrole as String)
        }
    }

    private func readStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: AnyObject?
        let res = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard res == .success else { return nil }
        return value as? String
    }

    private func readBoolAttribute(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var value: AnyObject?
        let res = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard res == .success else { return nil }
        if let num = value as? NSNumber {
            return num.boolValue
        }
        return nil
    }

    private func readPointAttribute(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: AnyObject?
        let res = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard res == .success, let axVal = value else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(axVal as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    private func readSizeAttribute(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: AnyObject?
        let res = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard res == .success, let axVal = value else { return nil }
        var size = CGSize.zero
        if AXValueGetValue(axVal as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }
}
