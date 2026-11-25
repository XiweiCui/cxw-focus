import AppKit
import FocusDockCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: FocusDockController
    @State private var selectedModeID: String?
    @State private var showAppPickerForMode = false
    @State private var showUtilityAppPicker = false
    @State private var isAccessibilityTrusted = WindowLayoutManager.isAccessibilityTrusted()
    @State private var copiedCLI = false

    private let symbolChoices = [
        "hammer.fill", "pencil.line", "book.fill", "terminal.fill",
        "sparkles", "brain.head.profile", "doc.text.fill", "cube.fill",
        "paintbrush.fill", "headphones"
    ]

    private let colorChoices = [
        "#3B82F6", "#D97706", "#10B981", "#8B5CF6",
        "#EC4899", "#EF4444", "#06B6D4", "#6366F1"
    ]

    var body: some View {
        TabView {
            modesTab
                .tabItem {
                    Label("档位管理", systemImage: "square.grid.2x2")
                }

            generalTab
                .tabItem {
                    Label("通用与白名单", systemImage: "slider.horizontal.3")
                }

            integrationTab
                .tabItem {
                    Label("权限与联动", systemImage: "bolt.shield")
                }
        }
        .frame(width: 640, height: 500)
        .onAppear {
            if selectedModeID == nil {
                selectedModeID = controller.activeModeID ?? controller.config.modes.first?.id
            }
            isAccessibilityTrusted = WindowLayoutManager.isAccessibilityTrusted()
            controller.refreshAvailableShortcuts()
        }
    }

    // MARK: - Tab 1: Modes

    private var modesTab: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectedModeID) {
                    ForEach(controller.config.modes) { mode in
                        HStack(spacing: 8) {
                            Image(systemName: mode.symbolName)
                                .foregroundColor(Color(hex: mode.accentHex))
                                .frame(width: 18)
                            Text(mode.name)
                                .lineLimit(1)
                            Spacer()
                            if controller.activeModeID == mode.id {
                                Circle()
                                    .fill(Color(hex: mode.accentHex))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .tag(mode.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 4) {
                    Button {
                        let created = controller.addMode()
                        selectedModeID = created.id
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("新建档位")

                    Button {
                        if let id = selectedModeID {
                            controller.deleteMode(id: id)
                            selectedModeID = controller.config.modes.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedModeID == nil || controller.config.modes.count <= 1)
                    .help("删除选中档位")

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(width: 180)

            Divider()

            if let modeIndex = controller.config.modes.firstIndex(where: { $0.id == selectedModeID }) {
                modeDetailEditor(index: modeIndex)
            } else {
                VStack {
                    Text("请在左侧选择一个档位")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func modeDetailEditor(index: Int) -> some View {
        let modeBinding = Binding<FocusModeConfig>(
            get: { controller.config.modes[index] },
            set: { updated in
                controller.config.modes[index] = updated
                controller.saveConfig()
            }
        )
        let mode = controller.config.modes[index]

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Identity
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("档位名称")
                            .font(.subheadline.weight(.medium))
                            .frame(width: 72, alignment: .leading)
                        TextField("例如：开发 / 写作", text: modeBinding.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(alignment: .top) {
                        Text("图标")
                            .font(.subheadline.weight(.medium))
                            .frame(width: 72, alignment: .leading)
                            .padding(.top, 4)

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 5), spacing: 6) {
                            ForEach(symbolChoices, id: \.self) { symbol in
                                let selected = mode.symbolName == symbol
                                Button {
                                    var copy = mode
                                    copy.symbolName = symbol
                                    controller.updateMode(copy)
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 13))
                                        .frame(width: 30, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(selected ? Color(hex: mode.accentHex).opacity(0.22) : Color.primary.opacity(0.05))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(selected ? Color(hex: mode.accentHex) : Color.clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack {
                        Text("主题色")
                            .font(.subheadline.weight(.medium))
                            .frame(width: 72, alignment: .leading)

                        HStack(spacing: 8) {
                            ForEach(colorChoices, id: \.self) { hex in
                                Button {
                                    var copy = mode
                                    copy.accentHex = hex
                                    controller.updateMode(copy)
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: mode.accentHex == hex ? 2 : 0)
                                        )
                                        .shadow(color: mode.accentHex == hex ? Color(hex: hex).opacity(0.5) : .clear, radius: 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Divider()

                // Preset Apps
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("预设白名单软件 (\(mode.presetAppBundleIDs.count))")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            showAppPickerForMode = true
                        } label: {
                            Label("添加软件", systemImage: "plus")
                        }
                        .controlSize(.small)
                        .popover(isPresented: $showAppPickerForMode) {
                            AddAppPopoverView(
                                controller: controller,
                                targetModeID: mode.id,
                                allowTemporary: false,
                                onDismiss: { showAppPickerForMode = false }
                            )
                        }
                    }

                    if mode.presetAppBundleIDs.isEmpty {
                        Text("暂无预设软件，点击右上角「添加软件」")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(mode.presetAppBundleIDs, id: \.self) { bid in
                                let entry = controller.appCatalog.entry(for: bid)
                                HStack(spacing: 10) {
                                    Image(nsImage: entry.icon)
                                        .resizable()
                                        .frame(width: 22, height: 22)
                                        .cornerRadius(5)
                                    Text(entry.name)
                                        .font(.system(size: 13))
                                    Text(bid)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        controller.removePresetApp(bundleID: bid, from: mode.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
                            }
                        }
                    }
                }

                Divider()

                // Window layout snapshot
                VStack(alignment: .leading, spacing: 8) {
                    Text("窗口布局记忆")
                        .font(.subheadline.weight(.semibold))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if mode.windowLayout.isEmpty {
                                Text("当前未保存布局（切入时保持窗口原位不动）")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("已记住 \(mode.windowLayout.count) 个窗口的位置与大小")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        Spacer()
                        Button("记住当前布局") {
                            controller.saveCurrentWindowLayout(for: mode.id)
                            isAccessibilityTrusted = WindowLayoutManager.isAccessibilityTrusted()
                        }
                        .controlSize(.small)

                        if !mode.windowLayout.isEmpty {
                            Button("清除") {
                                controller.clearWindowLayout(for: mode.id)
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }

                Divider()

                // Notification Shortcut
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("切入时静音通知（快捷指令）")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            controller.refreshAvailableShortcuts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("刷新快捷指令列表")
                    }

                    Picker("触发快捷指令", selection: Binding<String>(
                        get: { mode.shortcutOnEnter ?? "" },
                        set: { newValue in
                            var copy = mode
                            copy.shortcutOnEnter = newValue.isEmpty ? nil : newValue
                            controller.updateMode(copy)
                        }
                    )) {
                        Text("不自动切换通知").tag("")
                        ForEach(controller.availableShortcuts, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()

                    Text("提示：在系统「快捷指令」App 中创建一个包含「设定专注模式」动作的指令即可在此绑定。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(18)
        }
    }

    // MARK: - Tab 2: General & Utility Whitelist

    private var generalTab: some View {
        let settingsBinding = Binding<AppSettings>(
            get: { controller.config.settings },
            set: { updated in
                controller.config.settings = updated
                controller.saveConfig()
            }
        )

        return Form {
            Section("沉浸行为") {
                Picker("沉浸时底部 Dock", selection: Binding<Bool>(
                    get: { controller.config.settings.autoHideFloatingDockInImmersive },
                    set: { newVal in
                        controller.config.settings.autoHideFloatingDockInImmersive = newVal
                        controller.saveConfig()
                    }
                )) {
                    Text("常驻显示").tag(false)
                    Text("自动隐藏（移到底部呼出）").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("进入沉浸模式时完全屏蔽系统原生 Dock", isOn: settingsBinding.autoHideSystemDock)
                Toggle("沉浸时隐藏桌面文件与小组件", isOn: settingsBinding.hideDesktopItemsInImmersive)
                Toggle("沉浸时隐藏顶部多余状态栏图标（仅留当前档位与时间）", isOn: settingsBinding.hideMenuBarIconsInImmersive)
                Toggle("在 Dock 右侧显示最小化的窗口", isOn: Binding<Bool>(
                    get: { controller.config.settings.showMinimizedWindowsInDock },
                    set: { newVal in
                        controller.config.settings.showMinimizedWindowsInDock = newVal
                        controller.saveConfig()
                        if newVal && controller.isInImmersiveMode {
                            controller.refreshMinimizedWindows()
                            controller.startMinimizedRefreshTimer()
                        } else {
                            controller.stopMinimizedRefreshTimer()
                            controller.minimizedWindows = []
                        }
                    }
                ))
                Toggle("自由模式下隐藏底部 CXW focus 悬浮条", isOn: Binding<Bool>(
                    get: { controller.config.settings.hideFloatingDockWhenFree },
                    set: { newVal in
                        controller.config.settings.hideFloatingDockWhenFree = newVal
                        controller.saveConfig()
                        if !controller.isInImmersiveMode {
                            if newVal {
                                controller.hideFloatingDock()
                            } else {
                                controller.showFloatingDock()
                            }
                        }
                    }
                ))
                Toggle("拦截非白名单软件时在底部提示", isOn: settingsBinding.showBlockedToast)
            }

            Section("退出沉浸时通知恢复") {
                Picker("退出时触发快捷指令", selection: Binding<String>(
                    get: { controller.config.settings.shortcutOnExit ?? "" },
                    set: { newVal in
                        controller.config.settings.shortcutOnExit = newVal.isEmpty ? nil : newVal
                        controller.saveConfig()
                    }
                )) {
                    Text("不执行快捷指令").tag("")
                    ForEach(controller.availableShortcuts, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("这些软件在所有沉浸档位下默认放行，不会占用底部 Dock 栏位置。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showUtilityAppPicker = true
                        } label: {
                            Label("添加", systemImage: "plus")
                        }
                        .controlSize(.small)
                        .popover(isPresented: $showUtilityAppPicker) {
                            utilityAppPickerView
                        }
                    }

                    ForEach(controller.config.settings.utilityWhitelistBundleIDs, id: \.self) { bid in
                        let entry = controller.appCatalog.entry(for: bid)
                        HStack {
                            Image(nsImage: entry.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                                .cornerRadius(4)
                            Text(entry.name)
                            Spacer()
                            Text(bid)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button {
                                controller.config.settings.utilityWhitelistBundleIDs.removeAll { $0 == bid }
                                controller.saveConfig()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("基础辅助软件白名单")
            }
        }
        .formStyle(.grouped)
    }

    private var utilityAppPickerView: some View {
        let existing = Set(controller.config.settings.utilityWhitelistBundleIDs)
        let candidates = controller.appCatalog.installedApps.filter { !existing.contains($0.id) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("选择要始终放行的辅助软件")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(candidates) { entry in
                        Button {
                            controller.config.settings.utilityWhitelistBundleIDs.append(entry.id)
                            controller.saveConfig()
                            showUtilityAppPicker = false
                        } label: {
                            HStack {
                                Image(nsImage: entry.icon)
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                Text(entry.name)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 280, height: 320)
    }

    // MARK: - Tab 3: Permissions & Integration

    private var integrationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Accessibility card
                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 26))
                            .foregroundColor(isAccessibilityTrusted ? .green : .orange)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("辅助功能权限（窗口布局记忆与还原）")
                                .font(.subheadline.weight(.semibold))
                            Text(isAccessibilityTrusted ? "已授权，可以正常保存并还原各档位的窗口位置。" : "未授权：基础白名单拦截可用，但无法读写窗口位置。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(isAccessibilityTrusted ? "重新检查" : "前往授权") {
                            if !WindowLayoutManager.isAccessibilityTrusted() {
                                WindowLayoutManager.requestAccessibilityPermission()
                            }
                            isAccessibilityTrusted = WindowLayoutManager.isAccessibilityTrusted()
                        }
                        .controlSize(.small)
                    }
                    .padding(6)
                }

                // Shortcuts guide
                GroupBox("按档位静音不同通知（macOS 专注模式配置）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 打开系统「设置 → 专注模式」，为不同场景新建专注模式（例如“开发专注”仅放行终端与 AGY，“写作专注”全部静音）。")
                        Text("2. 打开 Apple「快捷指令」App，新建快捷指令并添加「设定专注模式」动作（以及一个关闭专注模式的快捷指令）。")
                        Text("3. 回到本窗口「档位管理」与「通用设置」中绑定对应快捷指令名称，切档时会自动静音通知。")
                        HStack {
                            Button("打开快捷指令 App") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                            }
                            .controlSize(.small)

                            Button("刷新指令列表") {
                                controller.refreshAvailableShortcuts()
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, 2)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                // CLI & AGY integration
                GroupBox("CLI 与 AGY / Harness 联动") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("可在终端、快捷键工具或 AI Harness 中直接调用 `cxwfocus` 命令控制沉浸状态：")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        let cliExample = """
                        cxwfocus status
                        cxwfocus list
                        cxwfocus enter coding
                        cxwfocus add Obsidian
                        cxwfocus exit
                        """

                        Text(cliExample)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

                        HStack {
                            Text("URL Scheme: cxwfocus://enter/coding · cxwfocus://exit")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(copiedCLI ? "已复制" : "复制常用命令") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cliExample, forType: .string)
                                copiedCLI = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copiedCLI = false
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(6)
                }
            }
            .padding(18)
        }
    }
}
