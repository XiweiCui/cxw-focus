import AppKit
import Combine
import Foundation
import QuartzCore

@MainActor
final class DesktopCurtainController {
    private let controller: FocusDockController
    private var windows: [NSWindow] = []
    private var cachedWallpapers: [UInt32: NSImage] = [:]
    private var cachedScreenFrames: [NSRect] = []
    private var cancellables: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var isActive = false
    private var transitionGeneration: Int = 0

    init(controller: FocusDockController) {
        self.controller = controller
        preloadWallpaperCache()
        bindState()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.preloadWallpaperCache()
                self?.syncVisibility(animated: false, forceRebuild: true)
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private func bindState() {
        Publishers.CombineLatest(controller.$activeModeID, controller.$config)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                Task { @MainActor in
                    self?.syncVisibility(animated: true, forceRebuild: false)
                }
            }
            .store(in: &cancellables)
    }

    private func displayID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func preloadWallpaperCache() {
        let entries: [(UInt32, URL)] = NSScreen.screens.compactMap { screen in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            return (displayID(for: screen), url)
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var loaded: [UInt32: NSImage] = [:]
            for (id, url) in entries {
                if let img = NSImage(contentsOf: url) {
                    loaded[id] = img
                }
            }
            Task { @MainActor [weak self] in
                self?.cachedWallpapers = loaded
            }
        }
    }

    func syncVisibility(animated: Bool, forceRebuild: Bool = false) {
        let shouldShow = controller.isInImmersiveMode && controller.config.settings.hideDesktopItemsInImmersive
        if shouldShow {
            show(animated: animated, forceRebuild: forceRebuild)
        } else {
            hide(animated: animated)
        }
    }

    func show(animated: Bool, forceRebuild: Bool = false) {
        let currentFrames = NSScreen.screens.map(\.frame)
        let alreadyShowingSameScreens = isActive && !forceRebuild &&
            windows.count == currentFrames.count &&
            cachedScreenFrames == currentFrames

        if alreadyShowingSameScreens {
            return
        }

        transitionGeneration += 1
        rebuildWindows()
        cachedScreenFrames = currentFrames
        isActive = true

        for win in windows {
            if animated {
                win.alphaValue = 0
                win.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.26
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                    win.animator().alphaValue = 1
                }
            } else {
                win.alphaValue = 1
                win.orderFrontRegardless()
            }
        }
    }

    func hide(animated: Bool) {
        guard isActive || !windows.isEmpty else { return }
        transitionGeneration += 1
        let gen = transitionGeneration
        isActive = false
        let currentWindows = windows
        windows = []
        cachedScreenFrames = []

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for win in currentWindows {
                    win.animator().alphaValue = 0
                }
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    _ = self
                    _ = gen
                    for win in currentWindows {
                        win.orderOut(nil)
                    }
                }
            })
        } else {
            for win in currentWindows {
                win.orderOut(nil)
            }
        }
    }

    private func rebuildWindows() {
        for win in windows {
            win.orderOut(nil)
        }
        windows = NSScreen.screens.map { screen in
            makeCurtainWindow(for: screen)
        }
    }

    private func makeCurtainWindow(for screen: NSScreen) -> NSWindow {
        // Place strictly above desktop icons (-2147483603) and desktop widgets (-2147483601),
        // while staying below all normal app windows (0) and the floating Dock (3).
        let levelValue = Int(CGWindowLevelForKey(.normalWindow)) - 1
        // Stop cleanly at the bottom edge of the top menu bar so macOS doesn't turn the left menu bar dark.
        let curtainHeight = max(1, screen.visibleFrame.maxY - screen.frame.minY)
        let curtainFrame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: curtainHeight
        )
        let window = NSWindow(
            contentRect: curtainFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: levelValue)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.557, green: 0.573, blue: 0.600, alpha: 1.0)

        let containerView = NSView(frame: NSRect(origin: .zero, size: curtainFrame.size))
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor(red: 0.557, green: 0.573, blue: 0.600, alpha: 1.0).cgColor

        let id = displayID(for: screen)
        if let cached = cachedWallpapers[id] {
            containerView.layer?.contents = cached
            containerView.layer?.contentsGravity = .resizeAspectFill
        } else if let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  let image = NSImage(contentsOf: url) {
            cachedWallpapers[id] = image
            containerView.layer?.contents = image
            containerView.layer?.contentsGravity = .resizeAspectFill
        }

        window.contentView = containerView
        window.setFrame(curtainFrame, display: true)
        return window
    }
}
