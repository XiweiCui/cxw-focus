import AppKit
import Combine
import FocusDockCore
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var controller: FocusDockController
    let onClosePopover: () -> Void
    let onOpenAddApp: () -> Void
    let onOpenSettings: () -> Void
    let onQuitApp: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsedString: String {
        guard let start = controller.sessionStartDate else { return "00:00" }
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                if let activeMode = controller.activeMode {
                    Image(systemName: activeMode.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(hex: activeMode.accentHex)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(activeMode.name) · 沉浸中")
                            .font(.system(size: 14, weight: .semibold))
                        Text("已专注 \(elapsedString)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("退出沉浸") {
                        onClosePopover()
                        DispatchQueue.main.async {
                            controller.requestExitImmersiveMode(skipConfirmation: false)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                } else {
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.primary.opacity(0.08)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CXW focus · 自由模式")
                            .font(.system(size: 14, weight: .semibold))
                        Text("点击下方档位开始专注")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            Divider()

            // Mode cards
            VStack(alignment: .leading, spacing: 6) {
                Text("沉浸档位")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                ForEach(controller.config.modes) { mode in
                    let isActive = controller.activeModeID == mode.id
                    Button {
                        onClosePopover()
                        controller.enterMode(id: mode.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isActive ? .white : Color(hex: mode.accentHex))
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isActive ? Color(hex: mode.accentHex) : Color(hex: mode.accentHex).opacity(0.14))
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("\(mode.presetAppBundleIDs.count) 个预设软件" + (mode.windowLayout.isEmpty ? "" : " · 已存布局"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if isActive {
                                Text("当前")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(hex: mode.accentHex))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color(hex: mode.accentHex).opacity(0.14)))
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isActive ? Color(hex: mode.accentHex).opacity(0.10) : Color.primary.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if controller.isInImmersiveMode {
                Divider()
                HStack(spacing: 8) {
                    Button {
                        controller.saveCurrentWindowLayout()
                    } label: {
                        Label("记住窗口布局", systemImage: "macwindow.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onClosePopover()
                        onOpenAddApp()
                    } label: {
                        Label("临时加软件", systemImage: "plus.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !WindowLayoutManager.isAccessibilityTrusted() {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("授权辅助功能后支持最小化窗口区与布局记忆")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    Button("授权") {
                        onClosePopover()
                        WindowLayoutManager.requestAccessibilityPermission()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.orange.opacity(0.09))
                )
            }

            Divider()

            HStack {
                if controller.isInImmersiveMode {
                    Button {
                        controller.config.settings.autoHideFloatingDockInImmersive.toggle()
                        controller.saveConfig()
                    } label: {
                        Label(
                            controller.config.settings.autoHideFloatingDockInImmersive ? "Dock 自动隐藏" : "Dock 常驻",
                            systemImage: controller.config.settings.autoHideFloatingDockInImmersive ? "dock.arrow.up.rectangle" : "dock.rectangle"
                        )
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                } else {
                    Button {
                        controller.toggleDockVisibility()
                    } label: {
                        Label(controller.isShowingDock ? "隐藏底部 Dock" : "显示底部 Dock", systemImage: "dock.rectangle")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                }

                Spacer()

                Button {
                    onClosePopover()
                    onOpenSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))

                Text("·")
                    .foregroundColor(.secondary)

                Button("退出") {
                    onQuitApp()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: 310)
        .onReceive(timer) { date in
            now = date
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    private let controller: FocusDockController
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    var onRequestOpenAddApp: (() -> Void)?
    var onRequestOpenSettings: (() -> Void)?

    init(controller: FocusDockController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        setupPopover()
        setupStatusButton()
        bindState()
        updateStatusItemAppearance()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        let rootView = MenuBarPopoverView(
            controller: controller,
            onClosePopover: { [weak self] in
                self?.popover.performClose(nil)
            },
            onOpenAddApp: { [weak self] in
                self?.onRequestOpenAddApp?()
            },
            onOpenSettings: { [weak self] in
                self?.onRequestOpenSettings?()
            },
            onQuitApp: {
                NSApp.terminate(nil)
            }
        )
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func setupStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func bindState() {
        Publishers.CombineLatest(controller.$activeModeID, controller.$config)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateStatusItemAppearance()
                self?.syncTimer()
            }
            .store(in: &cancellables)
    }

    private func syncTimer() {
        timer?.invalidate()
        timer = nil
        guard controller.isInImmersiveMode else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItemAppearance()
            }
        }
    }

    private func updateStatusItemAppearance() {
        let shouldHideStatusItem = controller.isInImmersiveMode && controller.config.settings.hideMenuBarIconsInImmersive
        statusItem.isVisible = !shouldHideStatusItem
        if shouldHideStatusItem && popover.isShown {
            popover.performClose(nil)
        }

        guard let button = statusItem.button else { return }

        if let mode = controller.activeMode {
            let image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.name)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading

            let elapsed: String
            if let start = controller.sessionStartDate {
                let sec = max(0, Int(Date().timeIntervalSince(start)))
                elapsed = String(format: "%02d:%02d", sec / 60, sec % 60)
            } else {
                elapsed = "00:00"
            }
            button.title = " \(mode.name) \(elapsed)"
        } else {
            let image = NSImage(systemSymbolName: "scope", accessibilityDescription: "CXW focus")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        }
    }

    func showPopover() {
        guard statusItem.isVisible, let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }
}
