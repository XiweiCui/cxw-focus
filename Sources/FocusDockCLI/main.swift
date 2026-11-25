import Darwin
import FocusDockCore
import Foundation

struct CLI {
    static func run() -> Int32 {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let subcommand = args.first else {
            printUsage()
            return 0
        }

        let jsonFlag = args.contains("--json")
        let forceFlag = args.contains("--force")
        let positional = args.dropFirst().filter { !$0.hasPrefix("--") }

        switch subcommand {
        case "--help", "-h", "help":
            printUsage()
            return 0

        case "status":
            return execute(IPCRequest(command: .status), jsonOutput: jsonFlag, autoLaunchIfNeeded: false)

        case "list":
            return execute(IPCRequest(command: .list), jsonOutput: jsonFlag, autoLaunchIfNeeded: false)

        case "enter":
            guard let target = positional.first, !target.isEmpty else {
                fputs("Error: 'enter' requires a mode ID or name (e.g. cxwfocus enter coding)\n", stderr)
                return 1
            }
            return execute(IPCRequest(command: .enter, target: target), jsonOutput: jsonFlag, autoLaunchIfNeeded: true)

        case "exit":
            return execute(IPCRequest(command: .exit, force: forceFlag), jsonOutput: jsonFlag, autoLaunchIfNeeded: false)

        case "add":
            guard let target = positional.first, !target.isEmpty else {
                fputs("Error: 'add' requires an app name or bundle ID (e.g. cxwfocus add Obsidian)\n", stderr)
                return 1
            }
            return execute(IPCRequest(command: .add, target: target), jsonOutput: jsonFlag, autoLaunchIfNeeded: false)

        case "remove":
            guard let target = positional.first, !target.isEmpty else {
                fputs("Error: 'remove' requires an app name or bundle ID\n", stderr)
                return 1
            }
            return execute(IPCRequest(command: .remove, target: target), jsonOutput: jsonFlag, autoLaunchIfNeeded: false)

        case "save-layout":
            return execute(IPCRequest(command: .saveLayout), jsonOutput: jsonFlag, autoLaunchIfNeeded: false)

        default:
            fputs("Unknown command: \(subcommand)\n", stderr)
            printUsage()
            return 1
        }
    }

    private static func execute(_ request: IPCRequest, jsonOutput: Bool, autoLaunchIfNeeded: Bool) -> Int32 {
        let socketPath = FocusDockPaths.socketURL().path

        if autoLaunchIfNeeded && !canConnect(socketPath: socketPath) {
            if launchApp() {
                let deadline = Date().addingTimeInterval(3.0)
                while Date() < deadline {
                    if canConnect(socketPath: socketPath) {
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }

        do {
            let response = try send(request, socketPath: socketPath)
            if jsonOutput {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(response)
                if let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                printHumanReadable(response, command: request.command)
            }
            return response.ok ? 0 : 1
        } catch {
            if jsonOutput {
                let fallback = IPCResponse(ok: false, message: error.localizedDescription)
                if let data = try? JSONEncoder().encode(fallback),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                fputs("CXW focus is not running or unreachable (\(error.localizedDescription)).\n", stderr)
            }
            return 1
        }
    }

    private static func printHumanReadable(_ response: IPCResponse, command: IPCCommand) {
        if !response.ok {
            fputs("Error: \(response.message)\n", stderr)
            return
        }

        switch command {
        case .status:
            guard let st = response.status else {
                print(response.message)
                return
            }
            if st.state == "immersive" {
                let mins = (st.elapsedSeconds ?? 0) / 60
                let secs = (st.elapsedSeconds ?? 0) % 60
                print("State: immersive | Mode: \(st.activeModeName ?? "") (\(st.activeModeID ?? "")) | Elapsed: \(String(format: "%02d:%02d", mins, secs))")
                print("Preset apps: \(st.presetAppBundleIDs.joined(separator: ", "))")
                if !st.temporaryAppBundleIDs.isEmpty {
                    print("Temporary apps: \(st.temporaryAppBundleIDs.joined(separator: ", "))")
                }
            } else {
                print("State: free (CXW focus ready)")
            }

        case .list:
            guard let modes = response.modes else {
                print(response.message)
                return
            }
            for mode in modes {
                let activeTag = (response.status?.activeModeID == mode.id) ? " [ACTIVE]" : ""
                let layoutTag = mode.savedWindowCount > 0 ? " (\(mode.savedWindowCount) saved windows)" : ""
                print("- \(mode.id)\(activeTag): \(mode.name) | apps: \(mode.presetAppBundleIDs.joined(separator: ", "))\(layoutTag)")
            }

        default:
            print(response.message)
        }
    }

    private static func canConnect(socketPath: String) -> Bool {
        guard let fd = connectSocket(socketPath: socketPath) else { return false }
        close(fd)
        return true
    }

    private static func connectSocket(socketPath: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= maxLen else {
            close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            rawPtr.initializeMemory(as: UInt8.self, repeating: 0)
            for (idx, byte) in pathBytes.enumerated() {
                rawPtr[idx] = UInt8(bitPattern: byte)
            }
        }

        let res = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if res != 0 {
            close(fd)
            return nil
        }
        return fd
    }

    private static func send(_ request: IPCRequest, socketPath: String) throws -> IPCResponse {
        guard let fd = connectSocket(socketPath: socketPath) else {
            throw NSError(
                domain: "CXWFocusCLI",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Cannot connect to CXW focus socket at \(socketPath)"]
            )
        }
        defer { close(fd) }

        let payload = try IPCProtocol.encodeLine(request)
        try payload.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var totalWritten = 0
            while totalWritten < payload.count {
                let written = write(fd, base.advanced(by: totalWritten), payload.count - totalWritten)
                if written <= 0 {
                    throw NSError(domain: "CXWFocusCLI", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Socket write failed"])
                }
                totalWritten += written
            }
        }

        var responseData = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(fd, &chunk, chunk.count)
            if bytesRead <= 0 { break }
            responseData.append(chunk, count: bytesRead)
            if responseData.contains(0x0A) { break }
        }
        return try IPCProtocol.decodeResponse(from: responseData)
    }

    private static func launchApp() -> Bool {
        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates: [URL] = [
            // Inside CXW focus.app/Contents/Helpers/cxwfocus -> CXW focus.app
            exeURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
            // Alongside build/cxwfocus -> build/CXW focus.app
            exeURL.deletingLastPathComponent().appendingPathComponent("CXW focus.app"),
            URL(fileURLWithPath: "/Applications/CXW focus.app")
        ]

        for candidate in candidates where candidate.pathExtension == "app" && FileManager.default.fileExists(atPath: candidate.path) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-g", candidate.path, "--args", "--background"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            if (try? proc.run()) != nil {
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            }
        }
        return false
    }

    private static func printUsage() {
        print("""
        cxwfocus - CLI controller for CXW focus

        Usage:
          cxwfocus status [--json]
          cxwfocus list [--json]
          cxwfocus enter <mode-id-or-name> [--json]
          cxwfocus exit [--force] [--json]
          cxwfocus add <app-name-or-bundle-id> [--json]
          cxwfocus remove <app-name-or-bundle-id> [--json]
          cxwfocus save-layout [--json]
        """)
    }
}

exit(CLI.run())
