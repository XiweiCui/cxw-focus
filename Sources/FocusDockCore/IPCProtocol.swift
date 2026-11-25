import Foundation

public enum IPCProtocol {
    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A) // newline
        return data
    }

    public static func decodeRequest(from data: Data) throws -> IPCRequest {
        let trimmed = trimTrailingNewlines(data)
        return try JSONDecoder().decode(IPCRequest.self, from: trimmed)
    }

    public static func decodeResponse(from data: Data) throws -> IPCResponse {
        let trimmed = trimTrailingNewlines(data)
        return try JSONDecoder().decode(IPCResponse.self, from: trimmed)
    }

    private static func trimTrailingNewlines(_ data: Data) -> Data {
        var end = data.endIndex
        while end > data.startIndex {
            let prev = data.index(before: end)
            if data[prev] == 0x0A || data[prev] == 0x0D {
                end = prev
            } else {
                break
            }
        }
        return data[data.startIndex..<end]
    }
}
