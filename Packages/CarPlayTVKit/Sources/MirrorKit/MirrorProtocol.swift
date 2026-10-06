import Foundation

/// Messages from the broadcast extension to the app, over a loopback TCP connection.
///
/// Wire format: `[type: 1 byte][length: 4 bytes big-endian][payload]`.
public enum MirrorMessage: Equatable, Sendable {
    /// H.264 parameter sets; sent before every keyframe.
    case format(sps: Data, pps: Data)
    /// One encoded frame in AVCC form (4-byte length-prefixed NAL units).
    /// `orientation` is a `CGImagePropertyOrientation` raw value from ReplayKit.
    case frame(timestamp: Double, isKeyframe: Bool, orientation: UInt8, data: Data)

    public func encoded() -> Data {
        var payload = Data()
        let type: UInt8
        switch self {
        case .format(let sps, let pps):
            type = 1
            payload.appendUInt16(UInt16(sps.count))
            payload.append(sps)
            payload.appendUInt16(UInt16(pps.count))
            payload.append(pps)
        case .frame(let timestamp, let isKeyframe, let orientation, let data):
            type = 2
            payload.appendUInt64(timestamp.bitPattern)
            payload.append(isKeyframe ? 1 : 0)
            payload.append(orientation)
            payload.append(data)
        }
        var message = Data([type])
        message.appendUInt32(UInt32(payload.count))
        message.append(payload)
        return message
    }
}

public enum MirrorProtocol {
    /// Loopback port the app listens on while the car display is connected.
    public static let port: UInt16 = 47321
    /// Messages larger than this are treated as corrupt.
    static let maxPayload = 8 * 1024 * 1024
}

/// Reassembles messages from a TCP byte stream.
public struct MirrorStreamReader {
    private var buffer: [UInt8] = []
    public private(set) var isCorrupt = false

    public init() {}

    public mutating func append(_ data: Data) -> [MirrorMessage] {
        guard !isCorrupt else { return [] }
        buffer.append(contentsOf: data)
        var messages: [MirrorMessage] = []
        var offset = 0
        while buffer.count - offset >= 5 {
            let type = buffer[offset]
            let length = Int(readUInt32(at: offset + 1))
            guard length <= MirrorProtocol.maxPayload, type == 1 || type == 2 else {
                isCorrupt = true
                buffer = []
                return messages
            }
            guard buffer.count - offset - 5 >= length else { break }
            let start = offset + 5
            if let message = decode(type: type, payload: Array(buffer[start..<(start + length)])) {
                messages.append(message)
            }
            offset = start + length
        }
        if offset > 0 { buffer.removeFirst(offset) }
        return messages
    }

    private func readUInt32(at index: Int) -> UInt32 {
        buffer[index..<(index + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func decode(type: UInt8, payload: [UInt8]) -> MirrorMessage? {
        func uint(_ range: Range<Int>) -> UInt64 { payload[range].reduce(0) { ($0 << 8) | UInt64($1) } }
        switch type {
        case 1:
            guard payload.count >= 2 else { return nil }
            let spsLength = Int(uint(0..<2))
            guard payload.count >= 2 + spsLength + 2 else { return nil }
            let ppsLength = Int(uint((2 + spsLength)..<(4 + spsLength)))
            guard payload.count >= 4 + spsLength + ppsLength else { return nil }
            return .format(sps: Data(payload[2..<(2 + spsLength)]),
                           pps: Data(payload[(4 + spsLength)..<(4 + spsLength + ppsLength)]))
        case 2:
            guard payload.count >= 10 else { return nil }
            return .frame(timestamp: Double(bitPattern: uint(0..<8)), isKeyframe: payload[8] == 1,
                          orientation: payload[9], data: Data(payload[10...]))
        default:
            return nil
        }
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: (0..<4).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }

    mutating func appendUInt64(_ value: UInt64) {
        append(contentsOf: (0..<8).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
}
