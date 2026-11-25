import AppKit
import Combine
import QuartzCore
import SwiftUI

final class FloatingDockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DockPanelController {
    private let controller: FocusDockController
    private var panel: FloatingDockPanel?
    private var containerView: NSView?
    private var hostingView: NSHostingView<DockBarView>?
    private var addPopover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?

    // Cached geometry (updated only when layout changes, never on mouseMoved)
    private var cachedScreenFrame: NSRect = .zero
    private var cachedVisibleFrame: NSRect = .zero
    private var cachedHoverZone: NSRect = .zero

    // Auto-hide state
    private var isAutoHideCollapsed = false
    private var wasAutoHideModeActive = false
    private var lastObservedModeID: String?
    private var animationGeneration: Int = 0
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hoverPollTimer: Timer?
    private var hideDelayWorkItem: DispatchWorkItem?
    private var initialPeekUntil: Date?

    private let slideOffsetY: CGFloat = -48

    private var isAutoHideModeActive: Bool {
        controller.isInImmersiveMode && controller.config.settings.autoHideFloatingDockInImmersive
    }

    init(controller: FocusDockController) {
        self.controller = controller
        setupPanel()
        bindState()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        hoverPollTimer?.invalidate()
        hideDelayWorkItem?.cancel()
    }

    private func setupPanel() {
        let panel = FloatingDockPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = false

        let rootView = DockBarView(
            controller: controller,
            onOpenAddPopover: { [weak self] in
                self?.openAddAppPopover()
            },
            onOpenSettings: { [weak self] in
                self?.controller.onOpenSettingsRequested?()
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = container.bounds

        container.addSubview(hostingView)
        panel.contentView = container

        self.panel = panel
        self.containerView = container
        self.hostingView = hostingView

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.layoutPanel(animated: false)
            }
        }
    }

    private func bindState() {
        controller.$isShowingDock
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                if show {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            controller.$activeModeID,
            controller.$temporaryBundleIDs,
            controller.$config,
            controller.$blockedToastMessage
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] modeID, _, _, toast in
            Task { @MainActor in
                guard let self else { return }
                let modeChanged = (self.lastObservedModeID != modeID)
                self.lastObservedModeID = modeID
                self.recomputeGeometryCache()
                self.syncAutoHideMonitoring(modeChanged: modeChanged)
                if self.isAutoHideModeActive && toast != nil {
                    self.revealFromAutoHide(animated: true)
                }
                self.layoutPanel(animated: true)
            }
        }
        .store(in: &cancellables)

        controller.$minimizedWindows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.recomputeGeometryCache()
                    self?.layoutPanel(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        recomputeGeometryCache()
        syncAutoHideMonitoring(modeChanged: false)
        if isAutoHideModeActive && isAutoHideCollapsed {
            revealFromAutoHide(animated: false)
        } else {
            resetHostingLayerState()
            layoutPanel(animated: false)
            panel?.ignoresMouseEvents = false
            panel?.orderFrontRegardless()
        }
    }

    func hide() {
        addPopover?.performClose(nil)
        stopAutoHideMonitoring()
        animationGeneration += 1
        isAutoHideCollapsed = false
        resetHostingLayerState()
        panel?.ignoresMouseEvents = false
        panel?.orderOut(nil)
    }

    // MARK: - Geometry Cache & Layout

    private func targetScreenForDock() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private func recomputeGeometryCache() {
        guard let hostingView, let screen = targetScreenForDock() else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let x = screen.frame.midX - size.width / 2.0
        let bottomInset = DockBarView.shadowPaddingBottom
        let visibleDockTop: CGFloat
        if controller.isInImmersiveMode && controller.config.settings.autoHideSystemDock {
            visibleDockTop = screen.frame.minY + 10
        } else {
            visibleDockTop = max(screen.visibleFrame.minY + 10, screen.frame.minY + 10)
        }
        let panelY = visibleDockTop - bottomInset
        let vFrame = NSRect(x: round(x), y: round(panelY), width: ceil(size.width), height: ceil(size.height))

        let glassMinX = vFrame.minX + DockBarView.shadowPaddingHorizontal
        let glassMaxX = vFrame.maxX - DockBarView.shadowPaddingHorizontal
        let glassMaxY = vFrame.maxY - DockBarView.shadowPaddingTop
        let hZone = NSRect(
            x: glassMinX - 24,
            y: screen.frame.minY,
            width: (glassMaxX - glassMinX) + 48,
            height: (glassMaxY - screen.frame.minY) + 28
        )

        cachedScreenFrame = screen.frame
        cachedVisibleFrame = vFrame
        cachedHoverZone = hZone
    }

    func layoutPanel(animated: Bool) {
        recomputeGeometryCache()
        guard let panel, let hostingView, cachedVisibleFrame.width > 0 else { return }

        if panel.frame != cachedVisibleFrame {
            if animated && panel.isVisible && !(isAutoHideModeActive && isAutoHideCollapsed) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(cachedVisibleFrame, display: true)
                }
            } else {
                panel.setFrame(cachedVisibleFrame, display: false)
            }
        }
        if let containerView {
            hostingView.frame = containerView.bounds
        }
    }

    private func resetHostingLayerState() {
        guard let layer = hostingView?.layer else { return }
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        layer.opacity = 1.0
        CATransaction.commit()
    }

    // MARK: - Auto-Hide Hover Logic

    private func syncAutoHideMonitoring(modeChanged: Bool) {
        let active = isAutoHideModeActive
        if active {
            let justActivated = !wasAutoHideModeActive
            wasAutoHideModeActive = true
            startAutoHideMonitoring()
            if justActivated || modeChanged {
                initialPeekUntil = Date().addingTimeInterval(1.4)
                revealFromAutoHide(animated: !justActivated)
            }
        } else if wasAutoHideModeActive {
            wasAutoHideModeActive = false
            stopAutoHideMonitoring()
            animationGeneration += 1
            isAutoHideCollapsed = false
            resetHostingLayerState()
            if controller.isShowingDock, let panel {
                panel.ignoresMouseEvents = false
                layoutPanel(animated: true)
                panel.orderFrontRegardless()
            }
        }
    }

    private func startAutoHideMonitoring() {
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                Task { @MainActor in
                    self?.evaluateMouseAutoHide()
                }
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                Task { @MainActor in
                    self?.evaluateMouseAutoHide()
                }
                return event
            }
        }
        if hoverPollTimer == nil {
            hoverPollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.evaluateMouseAutoHide()
                }
            }
        }
    }

    private func stopAutoHideMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
        hideDelayWorkItem?.cancel()
        hideDelayWorkItem = nil
        initialPeekUntil = nil
    }

    private func evaluateMouseAutoHide() {
        guard isAutoHideModeActive, controller.isShowingDock, cachedScreenFrame.width > 0 else { return }

        let mouse = NSEvent.mouseLocation

        let keepRevealed: Bool
        if addPopover?.isShown == true || controller.blockedToastMessage != nil {
            keepRevealed = true
        } else if let peekUntil = initialPeekUntil, Date() < peekUntil {
            keepRevealed = true
        } else if isAutoHideCollapsed {
            keepRevealed = mouse.y <= cachedScreenFrame.minY + 6 &&
                mouse.x >= cachedScreenFrame.minX &&
                mouse.x <= cachedScreenFrame.maxX
        } else {
            keepRevealed = cachedHoverZone.contains(mouse)
        }

        if keepRevealed {
            hideDelayWorkItem?.cancel()
            hideDelayWorkItem = nil
            if isAutoHideCollapsed {
                revealFromAutoHide(animated: true)
            }
        } else if !isAutoHideCollapsed && hideDelayWorkItem == nil {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.hideDelayWorkItem = nil
                    self?.collapseForAutoHide(animated: true)
                }
            }
            hideDelayWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
        }
    }

    private func revealFromAutoHide(animated: Bool) {
        recomputeGeometryCache()
        guard let panel, let hostingView, let layer = hostingView.layer, cachedVisibleFrame.width > 0 else {
            return
        }

        animationGeneration += 1
        isAutoHideCollapsed = false
        panel.ignoresMouseEvents = false

        if panel.frame != cachedVisibleFrame {
            panel.setFrame(cachedVisibleFrame, display: false)
        }
        if let containerView {
            hostingView.frame = containerView.bounds
        }

        let wasVisible = panel.isVisible
        let collapsedTransform = CATransform3DMakeTranslation(0, slideOffsetY, 0)

        let fromTransform: CATransform3D
        let fromOpacity: Float
        if wasVisible {
            fromTransform = layer.presentation()?.transform ?? layer.transform
            fromOpacity = layer.presentation()?.opacity ?? layer.opacity
        } else {
            fromTransform = collapsedTransform
            fromOpacity = 0.0
        }

        layer.removeAllAnimations()
        if !wasVisible {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = animated ? collapsedTransform : CATransform3DIdentity
            layer.opacity = animated ? 0.0 : 1.0
            CATransaction.commit()
            panel.orderFrontRegardless()
        } else {
            panel.orderFrontRegardless()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        layer.opacity = 1.0
        CATransaction.commit()

        if animated {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.fromValue = NSValue(caTransform3D: fromTransform)
            spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.mass = 1.0
            spring.stiffness = 380
            spring.damping = 32
            spring.initialVelocity = 0
            spring.duration = spring.settlingDuration

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = fromOpacity
            fade.toValue = Float(1.0)
            fade.duration = 0.16
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

            layer.add(spring, forKey: "dockSlide")
            layer.add(fade, forKey: "dockFade")
        }
    }

    private func collapseForAutoHide(animated: Bool) {
        guard isAutoHideModeActive,
              addPopover?.isShown != true,
              controller.blockedToastMessage == nil,
              let panel,
              let layer = hostingView?.layer else {
            return
        }

        animationGeneration += 1
        let gen = animationGeneration
        isAutoHideCollapsed = true
        panel.ignoresMouseEvents = true

        let collapsedTransform = CATransform3DMakeTranslation(0, slideOffsetY, 0)
        let fromTransform = layer.presentation()?.transform ?? layer.transform
        let fromOpacity = layer.presentation()?.opacity ?? layer.opacity

        layer.removeAllAnimations()

        if animated && panel.isVisible {
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                Task { @MainActor in
                    guard let self, self.animationGeneration == gen, self.isAutoHideCollapsed else { return }
                    self.panel?.orderOut(nil)
                }
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = collapsedTransform
            layer.opacity = 0.0
            CATransaction.commit()

            let slide = CABasicAnimation(keyPath: "transform")
            slide.fromValue = NSValue(caTransform3D: fromTransform)
            slide.toValue = NSValue(caTransform3D: collapsedTransform)
            slide.duration = 0.20
            slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = fromOpacity
            fade.toValue = Float(0.0)
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

            layer.add(slide, forKey: "dockSlide")
            layer.add(fade, forKey: "dockFade")

            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = collapsedTransform
            layer.opacity = 0.0
            CATransaction.commit()
            panel.orderOut(nil)
        }
    }

    // MARK: - Add App Popover

    func openAddAppPopover() {
        guard let panel else { return }
        if isAutoHideModeActive && isAutoHideCollapsed {
            revealFromAutoHide(animated: false)
        }
        if let existing = addPopover, existing.isShown {
            existing.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let contentView = AddAppPopoverView(
            controller: controller,
            targetModeID: controller.activeModeID,
            allowTemporary: controller.isInImmersiveMode
        ) { [weak popover] in
            popover?.performClose(nil)
        }
        popover.contentViewController = NSHostingController(rootView: contentView)
        addPopover = popover

        guard let anchorView = panel.contentView else { return }
        let minimizedOffset: CGFloat
        if controller.config.settings.showMinimizedWindowsInDock && !controller.minimizedWindows.isEmpty {
            minimizedOffset = 15 + CGFloat(controller.minimizedWindows.count) * 52
        } else {
            minimizedOffset = 0
        }
        let anchorX = max(
            DockBarView.shadowPaddingHorizontal + 40,
            anchorView.bounds.maxX - DockBarView.shadowPaddingHorizontal - 48 - minimizedOffset
        )
        let anchorRect = NSRect(
            x: anchorX,
            y: anchorView.bounds.minY + DockBarView.shadowPaddingBottom + 10,
            width: 36,
            height: 36
        )
        panel.makeKey()
        popover.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .maxY)
    }
}
