import FocusDockCore
import SwiftUI

struct DockBarView: View {
    static let shadowPaddingHorizontal: CGFloat = 38
    static let shadowPaddingTop: CGFloat = 24
    static let shadowPaddingBottom: CGFloat = 36

    @ObservedObject var controller: FocusDockController
    let onOpenAddPopover: () -> Void
    let onOpenSettings: () -> Void

    @State private var hoveredModeID: String?
    @State private var hoveredAppID: String?
    @State private var hoveredMinimizedID: String?
    @State private var hoveredExit = false
    @State private var hoveredAdd = false
    @State private var hoveredSettings = false
    @State private var hoveredFreeDismiss = false

    private let dockCornerRadius: CGFloat = 20

    var body: some View {
        VStack(spacing: 10) {
            if let toast = controller.blockedToastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    ZStack {
                        AppleGlassBackgroundView(material: .popover, cornerRadius: 14)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.48), Color.white.opacity(0.14)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.6
                            )
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                modeStrip

                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: 1, height: 26)
                    .padding(.horizontal, 2)

                appStrip
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    AppleGlassBackgroundView(material: .popover, cornerRadius: dockCornerRadius)
                    RoundedRectangle(cornerRadius: dockCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                    RoundedRectangle(cornerRadius: dockCornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.50), Color.white.opacity(0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                }
            )
        }
        .padding(.horizontal, Self.shadowPaddingHorizontal)
        .padding(.top, Self.shadowPaddingTop)
        .padding(.bottom, Self.shadowPaddingBottom)
        .background(Color.clear)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: controller.activeModeID)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: controller.temporaryBundleIDs)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: controller.minimizedWindows)
        .animation(.easeInOut(duration: 0.18), value: controller.blockedToastMessage)
    }

    private var modeStrip: some View {
        HStack(spacing: 6) {
            ForEach(controller.config.modes) { mode in
                let isActive = controller.activeModeID == mode.id
                let isHovered = hoveredModeID == mode.id
                let accent = Color(hex: mode.accentHex)

                Button {
                    controller.enterMode(id: mode.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                        if isActive {
                            Text(mode.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(isActive ? .white : Color.primary.opacity(0.82))
                    .padding(.horizontal, isActive ? 13 : 0)
                    .frame(height: 36)
                    .frame(minWidth: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                isActive
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [accent, accent.opacity(0.86)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.13 : 0.06))
                            )
                    )
                    .shadow(
                        color: isActive ? accent.opacity(0.30) : .clear,
                        radius: 6,
                        y: 2
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredModeID = hovering ? mode.id : nil
                }
                .help(isActive ? "当前处于「\(mode.name)」模式" : "切换到「\(mode.name)」模式")
            }

            if controller.isInImmersiveMode {
                Button {
                    controller.requestExitImmersiveMode(skipConfirmation: false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(hoveredExit ? .white : Color.primary.opacity(0.75))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(hoveredExit ? Color.red.opacity(0.85) : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveredExit = $0 }
                .help("退出沉浸模式")
            }
        }
    }

    @ViewBuilder
    private var appStrip: some View {
        if let activeMode = controller.activeMode {
            let bundleIDs = WhitelistPolicy.combinedDockBundleIDs(
                for: activeMode,
                temporaryBundleIDs: controller.temporaryBundleIDs
            )

            HStack(spacing: 8) {
                ForEach(bundleIDs, id: \.self) { bundleID in
                    let entry = controller.appCatalog.entry(for: bundleID)
                    let isRunning = controller.runningBundleIDs.contains(bundleID)
                    let isFrontmost = controller.frontmostBundleID == bundleID
                    let isTemporary = controller.temporaryBundleIDs.contains(bundleID)
                    let isHovered = hoveredAppID == bundleID

                    Button {
                        controller.activateOrLaunchApp(bundleID: bundleID)
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: entry.icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 42, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .shadow(
                                        color: isFrontmost
                                        ? Color(hex: activeMode.accentHex).opacity(0.32)
                                        : Color.black.opacity(0.16),
                                        radius: isFrontmost ? 5 : 3,
                                        y: 1.5
                                    )
                                    .scaleEffect(isHovered ? 1.16 : 1.0)
                                    .offset(y: isHovered ? -3 : 0)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.72), value: isHovered)

                                if isTemporary {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 2, y: -2)
                                }
                            }

                            Circle()
                                .fill(
                                    isFrontmost
                                    ? Color(hex: activeMode.accentHex)
                                    : (isRunning ? Color.primary.opacity(0.50) : Color.clear)
                                )
                                .frame(width: 4, height: 4)
                        }
                        .frame(width: 46, height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredAppID = hovering ? bundleID : nil
                    }
                    .help(isTemporary ? "\(entry.name)（临时加入）" : entry.name)
                    .contextMenu {
                        Button("打开 / 聚焦「\(entry.name)」") {
                            controller.activateOrLaunchApp(bundleID: bundleID)
                        }
                        Divider()
                        if isTemporary {
                            Button("固定到「\(activeMode.name)」预设") {
                                controller.promoteTemporaryAppToPreset(bundleID: bundleID)
                            }
                            Button("从本次沉浸移出", role: .destructive) {
                                controller.removeTemporaryApp(bundleID: bundleID)
                            }
                        } else {
                            Button("从「\(activeMode.name)」移出", role: .destructive) {
                                controller.removePresetApp(bundleID: bundleID, from: activeMode.id)
                            }
                        }
                    }
                }

                Button {
                    onOpenAddPopover()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(Color.primary.opacity(0.82))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.primary.opacity(hoveredAdd ? 0.13 : 0.06))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveredAdd = $0 }
                .help("临时加入软件到当前档位")

                if controller.config.settings.showMinimizedWindowsInDock && !controller.minimizedWindows.isEmpty {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 1, height: 26)
                        .padding(.horizontal, 2)

                    ForEach(controller.minimizedWindows) { win in
                        let appEntry = controller.appCatalog.entry(for: win.bundleID)
                        let isHovered = hoveredMinimizedID == win.id

                        Button {
                            controller.restoreMinimizedWindow(win)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 2.5) {
                                        Circle().fill(Color.red.opacity(0.80)).frame(width: 3.5, height: 3.5)
                                        Circle().fill(Color.yellow.opacity(0.90)).frame(width: 3.5, height: 3.5)
                                        Circle().fill(Color.green.opacity(0.80)).frame(width: 3.5, height: 3.5)
                                        Spacer()
                                    }
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(Color.primary.opacity(0.28))
                                        .frame(width: 24, height: 2.5)
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(Color.primary.opacity(0.16))
                                        .frame(width: 18, height: 2.5)
                                    Spacer(minLength: 0)
                                }
                                .padding(5)
                                .frame(width: 42, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(nsColor: .windowBackgroundColor).opacity(isHovered ? 0.96 : 0.88))
                                )
                                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)

                                Image(nsImage: appEntry.icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                                    .offset(x: 3, y: 3)
                            }
                            .scaleEffect(isHovered ? 1.14 : 1.0)
                            .offset(y: isHovered ? -2 : 0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: isHovered)
                            .frame(width: 46, height: 44)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredMinimizedID = hovering ? win.id : nil
                        }
                        .help("恢复最小化窗口：\(win.title)")
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Text("自由模式 · 选择左侧档位进入沉浸")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.75))
                    .padding(.horizontal, 4)

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.primary.opacity(0.82))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.primary.opacity(hoveredSettings ? 0.13 : 0.06))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveredSettings = $0 }
                .help("档位管理与偏好设置")

                Button {
                    controller.hideFloatingDock()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.primary.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(hoveredFreeDismiss ? 0.13 : 0.06))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveredFreeDismiss = $0 }
                .help("隐藏底部 Dock")
            }
        }
    }
}
