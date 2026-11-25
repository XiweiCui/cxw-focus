import AppKit
import Combine
import FocusDockCore
import QuartzCore
import SwiftUI

struct TopStatusBarShieldView: View {
    @ObservedObject var controller: FocusDockController
    let backdropColor: Color
    let onOpenSettings: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let dateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日 EEE  HH:mm"
        return df
    }()

    var body: some View {
        ZStack(alignment: .trailing) {
            backdropColor
            VisualEffectView(
                material: .menu,
                blendingMode: .withinWindow,
                state: .active,
                cornerRadius: 0
            )

            HStack(spacing: 12) {
                if let activeMode = controller.activeMode {
                    Menu {
                        ForEach(controller.config.modes) { mode in
                            Button {
                                controller.enterMode(id: mode.id)
                            } label: {
                                if mode.id == activeMode.id {
                                    Label("当前：\(mode.name)", systemImage: "checkmark")
                                } else {
                                    Label("切换到「\(mode.name)」", systemImage: mode.symbolName)
                                }
                            }
                        }
                        Divider()
                        Button {
                            controller.config.settings.autoHideFloatingDockInImmersive.toggle()
                            controller.saveConfig()
                        } label: {
                            Label(
                                controller.config.settings.autoHideFloatingDockInImmersive
                                ? "底部 Dock：自动隐藏（切换为常驻）"
                                : "底部 Dock：常驻显示（切换为自动隐藏）",
                                systemImage: controller.config.settings.autoHideFloatingDockInImmersive
                                ? "dock.arrow.up.rectangle"
                                : "dock.rectangle"
                            )
                        }
                        Button("记住当前窗口布局") {
                            controller.saveCurrentWindowLayout()
                        }
                        Button("打开 CXW focus 设置...") {
                            onOpenSettings()
                        }
                        Divider()
                        Button("退出沉浸模式...") {
                            controller.requestExitImmersiveMode(skipConfirmation: false)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: activeMode.symbolName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(activeMode.name)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.10))
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Text(Self.dateTimeFormatter.string(from: now))
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.primary)
            }
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { date in
            now = date
        }
    }
}

final class TopStatusShieldPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct SampledBackdropColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let isDark: Bool

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    static let fallback = SampledBackdropColor(red: 0.557, green: 0.573, blue: 0.600, isDark: false)
}

@MainActor
final class TopStatusBarShieldController {
    private let controller: FocusDockController
    private var panels: [NSPanel] = []
    private var cachedBackdropByDisplay: [UInt32: SampledBackdropColor] = [:]
    private var cachedScreenFrames: [NSRect] = []
    private var cancellables: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var isActive = false
    private var transitionGeneration: Int = 0

    init(controller: FocusDockController) {
        self.controller = controller
        preloadBackdropCache()
        bindState()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.preloadBackdropCache()
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

    private func preloadBackdropCache() {
        let entries: [(UInt32, URL)] = NSScreen.screens.compactMap { screen in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            return (displayID(for: screen), url)
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var results: [UInt32: SampledBackdropColor] = [:]
            for (id, url) in entries {
                results[id] = Self.sampleTopRightWallpaperColor(from: url)
            }
            Task { @MainActor [weak self] in
                self?.cachedBackdropByDisplay = results
            }
        }
    }

    func syncVisibility(animated: Bool = true, forceRebuild: Bool = false) {
        let shouldShow = controller.isInImmersiveMode && controller.config.settings.hideMenuBarIconsInImmersive
        if shouldShow {
            show(animated: animated, forceRebuild: forceRebuild)
        } else {
            hide(animated: animated)
        }
    }

    func show(animated: Bool = true, forceRebuild: Bool = false) {
        let currentFrames = NSScreen.screens.map(\.frame)
        let canReuseExisting = isActive && !forceRebuild &&
            !panels.isEmpty &&
            cachedScreenFrames == currentFrames

        if canReuseExisting {
            return
        }

        transitionGeneration += 1
        rebuildPanels()
        cachedScreenFrames = currentFrames
        isActive = true

        for panel in panels {
            if animated {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                }
            } else {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
        }
    }

    func hide(animated: Bool = true) {
        guard isActive || !panels.isEmpty else { return }
        transitionGeneration += 1
        isActive = false
        let currentPanels = panels
        panels = []
        cachedScreenFrames = []

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for panel in currentPanels {
                    panel.animator().alphaValue = 0
                }
            }, completionHandler: {
                Task { @MainActor in
                    for panel in currentPanels {
                        panel.orderOut(nil)
                    }
                }
            })
        } else {
            for panel in currentPanels {
                panel.orderOut(nil)
            }
        }
    }

    private func rebuildPanels() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels = NSScreen.screens.compactMap { screen in
            makeShieldPanel(for: screen)
        }
    }

    private func makeShieldPanel(for screen: NSScreen) -> NSPanel? {
        let barRect: NSRect
        if let auxRight = screen.auxiliaryTopRightArea, auxRight.width > 0 {
            let bottomY = min(auxRight.minY, screen.visibleFrame.maxY)
            let height = max(24, screen.frame.maxY - bottomY)
            barRect = NSRect(x: auxRight.minX, y: bottomY, width: screen.frame.maxX - auxRight.minX, height: height)
        } else {
            let height = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
            let width = round(screen.frame.width * 0.55)
            barRect = NSRect(x: screen.frame.maxX - width, y: screen.frame.maxY - height, width: width, height: height)
        }

        let levelValue = Int(CGWindowLevelForKey(.statusWindow)) + 1
        let panel = TopStatusShieldPanel(
            contentRect: barRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: levelValue)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let id = displayID(for: screen)
        let sampled: SampledBackdropColor
        if let cached = cachedBackdropByDisplay[id] {
            sampled = cached
        } else if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            let computed = Self.sampleTopRightWallpaperColor(from: url)
            cachedBackdropByDisplay[id] = computed
            sampled = computed
        } else {
            sampled = .fallback
        }

        let nsColor = sampled.nsColor
        panel.backgroundColor = nsColor

        let view = TopStatusBarShieldView(
            controller: controller,
            backdropColor: Color(nsColor: nsColor),
            onOpenSettings: { [weak self] in
                self?.controller.onOpenSettingsRequested?()
            }
        )
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        panel.setFrame(barRect, display: true)
        return panel
    }

    private nonisolated static func sampleTopRightWallpaperColor(from url: URL) -> SampledBackdropColor {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .fallback
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .fallback
        }

        let cropX = max(0, Int(Double(cgImage.width) * 0.72))
        let cropW = max(1, cgImage.width - cropX)
        let cropH = max(1, Int(Double(cgImage.height) * 0.05))
        if let cropped = cgImage.cropping(to: CGRect(x: cropX, y: 0, width: cropW, height: cropH)) {
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        } else {
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return SampledBackdropColor(red: r, green: g, blue: b, isDark: luminance < 0.48)
    }
}
