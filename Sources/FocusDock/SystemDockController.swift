import Darwin
import Foundation

final class SystemDockController {
    private static let savedAutoHideKey = "CXWFocus.savedOriginalDockAutoHide"
    private static let legacySavedAutoHideKey = "FocusDock.savedOriginalDockAutoHide"
    private static let savedHasAutoHideDelayKey = "CXWFocus.savedHasOriginalDockAutoHideDelay"
    private static let savedAutoHideDelayKey = "CXWFocus.savedOriginalDockAutoHideDelay"

    private typealias GetAutoHideFn = @convention(c) () -> UInt8
    private typealias SetAutoHideFn = @convention(c) (UInt8) -> Void

    private var appServicesHandle: UnsafeMutableRawPointer?
    private var getAutoHideFn: GetAutoHideFn?
    private var setAutoHideFn: SetAutoHideFn?
    private let defaultsQueue = DispatchQueue(label: "com.cxw.focus.dockctrl", qos: .userInitiated)
    private var hasLockedSystemDockInSession = false
    private var sessionGeneration: Int = 0

    init() {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        if let handle = dlopen(path, RTLD_LAZY) {
            appServicesHandle = handle
            if let getSym = dlsym(handle, "CoreDockGetAutoHideEnabled") {
                getAutoHideFn = unsafeBitCast(getSym, to: GetAutoHideFn.self)
            }
            if let setSym = dlsym(handle, "CoreDockSetAutoHideEnabled") {
                setAutoHideFn = unsafeBitCast(setSym, to: SetAutoHideFn.self)
            }
        }
    }

    deinit {
        if let handle = appServicesHandle {
            dlclose(handle)
        }
    }

    func isAutoHideEnabled() -> Bool {
        if let getAutoHideFn {
            return getAutoHideFn() != 0
        }
        return readDockAutoHidePreference()
    }

    func setAutoHideEnabled(_ enabled: Bool) {
        if let setAutoHideFn {
            setAutoHideFn(enabled ? 1 : 0)
            return
        }
        _ = runProcess("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false"])
    }

    /// Saves pre-immersive Dock auto-hide and hover-delay preferences instantaneously via
    /// CFPreferences, triggers immediate smooth auto-hide via CoreDock SPI, and schedules
    /// the 10000s delay + Dock lock-in after the visual curtain finishes fading in.
    func hideSystemDockForImmersiveSession() {
        let defaults = UserDefaults.standard
        if hasLockedSystemDockInSession && defaults.object(forKey: Self.savedAutoHideKey) != nil {
            return
        }

        sessionGeneration += 1
        let gen = sessionGeneration

        if defaults.object(forKey: Self.savedAutoHideKey) == nil {
            let currentAutoHide = readDockAutoHidePreference()
            defaults.set(currentAutoHide, forKey: Self.savedAutoHideKey)

            let currentDelay = readDockAutoHideDelayPreference()
            if let currentDelay {
                defaults.set(true, forKey: Self.savedHasAutoHideDelayKey)
                defaults.set(currentDelay, forKey: Self.savedAutoHideDelayKey)
            } else {
                defaults.set(false, forKey: Self.savedHasAutoHideDelayKey)
                defaults.removeObject(forKey: Self.savedAutoHideDelayKey)
            }
        }

        hasLockedSystemDockInSession = true
        setAutoHideFn?(1)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
            guard let self, self.sessionGeneration == gen, self.hasLockedSystemDockInSession else {
                return
            }
            self.defaultsQueue.async { [weak self] in
                guard let self else { return }
                self.runProcess("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
                self.runProcess("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "10000"])
                self.runProcess("/usr/bin/killall", ["Dock"])
            }
        }
    }

    /// Restores the user's pre-immersive Dock auto-hide & hover-delay preferences if saved.
    func restoreSystemDockIfNeeded(synchronous: Bool = false) {
        sessionGeneration += 1

        let defaults = UserDefaults.standard
        let autoHideKey: String
        if defaults.object(forKey: Self.savedAutoHideKey) != nil {
            autoHideKey = Self.savedAutoHideKey
        } else if defaults.object(forKey: Self.legacySavedAutoHideKey) != nil {
            autoHideKey = Self.legacySavedAutoHideKey
        } else {
            return
        }

        let originalAutoHide = defaults.bool(forKey: autoHideKey)
        let hadOriginalDelay = defaults.bool(forKey: Self.savedHasAutoHideDelayKey)
        let originalDelay = defaults.double(forKey: Self.savedAutoHideDelayKey)

        defaults.removeObject(forKey: Self.savedAutoHideKey)
        defaults.removeObject(forKey: Self.legacySavedAutoHideKey)
        defaults.removeObject(forKey: Self.savedHasAutoHideDelayKey)
        defaults.removeObject(forKey: Self.savedAutoHideDelayKey)
        hasLockedSystemDockInSession = false

        let restoreWork = { [weak self] in
            guard let self else { return }
            self.runProcess("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", originalAutoHide ? "true" : "false"])
            if hadOriginalDelay {
                self.runProcess("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "\(originalDelay)"])
            } else {
                self.runProcess("/usr/bin/defaults", ["delete", "com.apple.dock", "autohide-delay"])
            }
            self.runProcess("/usr/bin/killall", ["Dock"])
        }

        if synchronous {
            defaultsQueue.sync(execute: restoreWork)
        } else {
            defaultsQueue.async(execute: restoreWork)
        }
    }

    /// Call on launch in Free Mode to undo any leftover locked Dock from an unexpected termination.
    func recoverIfNeededOnLaunch() {
        restoreSystemDockIfNeeded(synchronous: true)
    }

    private func readDockAutoHidePreference() -> Bool {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        if let value = CFPreferencesCopyAppValue("autohide" as CFString, domain) as? NSNumber {
            return value.boolValue
        }
        return isAutoHideEnabled()
    }

    private func readDockAutoHideDelayPreference() -> Double? {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        if let value = CFPreferencesCopyAppValue("autohide-delay" as CFString, domain) as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    @discardableResult
    private func runProcess(_ path: String, _ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            return -1
        }
    }
}
