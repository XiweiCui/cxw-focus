import AppKit
import Foundation

public struct AppEntry: Identifiable, Hashable {
    public let id: String // bundleID
    public let name: String
    public let bundleURL: URL?
    public let icon: NSImage
    public let isInstalled: Bool

    public init(id: String, name: String, bundleURL: URL?, icon: NSImage, isInstalled: Bool) {
        self.id = id
        self.name = name
        self.bundleURL = bundleURL
        self.icon = icon
        self.isInstalled = isInstalled
    }

    public static func == (lhs: AppEntry, rhs: AppEntry) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.bundleURL == rhs.bundleURL && lhs.isInstalled == rhs.isInstalled
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var installedApps: [AppEntry] = []
    private var cache: [String: AppEntry] = [:]

    private static let searchDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    ]

    init() {
        refreshInstalledApps()
    }

    func refreshInstalledApps() {
        var found: [String: AppEntry] = [:]
        let fm = FileManager.default

        for dir in Self.searchDirectories where fm.fileExists(atPath: dir.path) {
            scanDirectory(dir, maxDepth: 2, into: &found)
        }

        // Also include currently running regular apps that might live elsewhere
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, found[bid] == nil else { continue }
            let name = app.localizedName ?? bid
            let icon = app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            let entry = AppEntry(
                id: bid,
                name: name,
                bundleURL: app.bundleURL,
                icon: icon,
                isInstalled: app.bundleURL != nil
            )
            found[bid] = entry
        }

        for (bid, entry) in found {
            cache[bid] = entry
        }

        installedApps = found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func scanDirectory(_ directory: URL, maxDepth: Int, into found: inout [String: AppEntry]) {
        guard maxDepth >= 0 else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in items {
            if url.pathExtension.lowercased() == "app" {
                if let entry = makeEntry(from: url) {
                    if found[entry.id] == nil {
                        found[entry.id] = entry
                    }
                }
            } else if maxDepth > 0 {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir && !url.lastPathComponent.hasSuffix(".localized") {
                    scanDirectory(url, maxDepth: maxDepth - 1, into: &found)
                }
            }
        }
    }

    private func makeEntry(from url: URL) -> AppEntry? {
        guard let bundle = Bundle(url: url),
              let bid = bundle.bundleIdentifier,
              !bid.isEmpty else {
            return nil
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return AppEntry(id: bid, name: name, bundleURL: url, icon: icon, isInstalled: true)
    }

    func entry(for bundleID: String) -> AppEntry {
        if let cached = cache[bundleID] {
            return cached
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let created = makeEntry(from: url) {
            cache[bundleID] = created
            return created
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            let icon = running.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            let entry = AppEntry(
                id: bundleID,
                name: running.localizedName ?? bundleID,
                bundleURL: running.bundleURL,
                icon: icon,
                isInstalled: running.bundleURL != nil
            )
            cache[bundleID] = entry
            return entry
        }
        let fallbackIcon = NSWorkspace.shared.icon(for: .applicationBundle)
        let fallback = AppEntry(id: bundleID, name: bundleID, bundleURL: nil, icon: fallbackIcon, isInstalled: false)
        cache[bundleID] = fallback
        return fallback
    }

    func runningRegularApps() -> [AppEntry] {
        var result: [AppEntry] = []
        var seen: Set<String> = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, seen.insert(bid).inserted else { continue }
            result.append(entry(for: bid))
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func resolveBundleID(fromQuery query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Direct bundle ID match if it looks like reverse DNS or matches an installed/running app
        if let exact = installedApps.first(where: { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact.id
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) != nil {
            return trimmed
        }
        if let exactName = installedApps.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exactName.id
        }
        if let partialName = installedApps.first(where: { $0.name.localizedCaseInsensitiveContains(trimmed) }) {
            return partialName.id
        }
        if trimmed.contains(".") {
            return trimmed
        }
        return nil
    }
}
