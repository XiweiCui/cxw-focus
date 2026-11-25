import FocusDockCore
import SwiftUI

struct AddAppPopoverView: View {
    @ObservedObject var controller: FocusDockController
    let targetModeID: String?
    let allowTemporary: Bool
    let onDismiss: () -> Void

    @State private var searchText: String = ""

    private var existingBundleIDs: Set<String> {
        var set: Set<String> = [Bundle.main.bundleIdentifier ?? WhitelistPolicy.defaultSelfBundleID]
        if let targetModeID,
           let mode = controller.config.modes.first(where: { $0.id == targetModeID }) {
            set.formUnion(mode.presetAppBundleIDs)
        }
        if allowTemporary {
            set.formUnion(controller.temporaryBundleIDs)
        }
        return set
    }

    private var filteredRunning: [AppEntry] {
        let existing = existingBundleIDs
        return controller.appCatalog.runningRegularApps().filter { entry in
            guard !existing.contains(entry.id) else { return false }
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            return entry.name.localizedCaseInsensitiveContains(searchText) ||
                entry.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredInstalled: [AppEntry] {
        let existing = existingBundleIDs
        let runningIDs = Set(filteredRunning.map(\.id))
        return controller.appCatalog.installedApps.filter { entry in
            guard !existing.contains(entry.id), !runningIDs.contains(entry.id) else { return false }
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            return entry.name.localizedCaseInsensitiveContains(searchText) ||
                entry.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索软件名称...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.05))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !filteredRunning.isEmpty {
                        sectionHeader("正在运行")
                        ForEach(filteredRunning) { entry in
                            appRow(entry)
                        }
                    }

                    if !filteredInstalled.isEmpty {
                        sectionHeader("已安装软件")
                        ForEach(filteredInstalled) { entry in
                            appRow(entry)
                        }
                    }

                    if filteredRunning.isEmpty && filteredInstalled.isEmpty {
                        Text("没有匹配的软件")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 28)
                    }
                }
                .padding(8)
            }

            if allowTemporary {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("「临时加入」会在退出沉浸模式后自动清空")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03))
            }
        }
        .frame(width: 340, height: 380)
        .onAppear {
            controller.appCatalog.refreshInstalledApps()
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func appRow(_ entry: AppEntry) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: entry.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if isLikelyBrowser(entry.id) {
                    Text("浏览器 · 不建议加入沉浸档")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }

            Spacer(minLength: 4)

            if allowTemporary {
                Button("临时加入") {
                    controller.addTemporaryApp(bundleID: entry.id)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let modeID = targetModeID {
                    Button("固定") {
                        controller.addPresetApp(bundleID: entry.id, to: modeID)
                        controller.activateOrLaunchApp(bundleID: entry.id)
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("永久加入当前档位预设")
                }
            } else if let modeID = targetModeID {
                Button("添加") {
                    controller.addPresetApp(bundleID: entry.id, to: modeID)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func isLikelyBrowser(_ bundleID: String) -> Bool {
        let lower = bundleID.lowercased()
        let browserIDs = [
            "com.google.chrome", "com.apple.safari", "org.mozilla.firefox",
            "company.thebrowser.browser", "com.microsoft.edgemac", "com.brave.browser",
            "com.operasoftware.opera", "com.vivaldi.vivaldi"
        ]
        return browserIDs.contains(lower) || lower.contains("browser")
    }
}
