import Darwin
import FocusDockCore
import Foundation

final class IPCServer {
    typealias RequestHandler = @MainActor (IPCRequest) -> IPCResponse

    private let socketPath: String
    private let handler: RequestHandler
    private let queue = DispatchQueue(label: "com.cxw.focus.ipc.server", qos: .userInitiated)
    private var listenFD: Int32 = -1
    private var isRunning = false

    init(socketURL: URL = FocusDockPaths.socketURL(), handler: @escaping RequestHandler) {
        self.socketPath = socketURL.path
        self.handler = handler
    }

    func start() {
        queue.async { [weak self] in
            self?.setupAndListen()
        }
    }

    func stop() {
        isRunning = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    private func setupAndListen() {
        let socketURL = URL(fileURLWithPath: socketPath)
        let dir = socketURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= maxLen else {
            close(fd)
            return
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            rawPtr.initializeMemory(as: UInt8.self, repeating: 0)
            for (idx, byte) in pathBytes.enumerated() {
                rawPtr[idx] = UInt8(bitPattern: byte)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return
        }

        guard listen(fd, 16) == 0 else {
            close(fd)
            unlink(socketPath)
            return
        }

        listenFD = fd
        isRunning = true

        while isRunning {
            let clientFD = accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            handleClient(clientFD)
        }
    }

    private func handleClient(_ clientFD: Int32) {
        defer { close(clientFD) }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(clientFD, &chunk, chunk.count)
            if bytesRead <= 0 {
                break
            }
            buffer.append(chunk, count: bytesRead)
            if buffer.contains(0x0A) || buffer.count >= 65536 {
                break
            }
        }

        let response: IPCResponse
        do {
            let request = try IPCProtocol.decodeRequest(from: buffer)
            let sem = DispatchSemaphore(value: 0)
            var resultBox: IPCResponse?
            let handler = self.handler
            Task { @MainActor in
                resultBox = handler(request)
                sem.signal()
            }
            sem.wait()
            response = resultBox ?? IPCResponse(ok: false, message: "Internal error")
        } catch {
            response = IPCResponse(ok: false, message: "Invalid IPC request: \(error.localizedDescription)")
        }

        if let encoded = try? IPCProtocol.encodeLine(response) {
            encoded.withUnsafeBytes { rawBuf in
                guard let base = rawBuf.baseAddress else { return }
                var totalWritten = 0
                while totalWritten < encoded.count {
                    let written = write(clientFD, base.advanced(by: totalWritten), encoded.count - totalWritten)
                    if written <= 0 { break }
                    totalWritten += written
                }
            }
        }
    }
}
