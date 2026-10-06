import Foundation

/// An audio or subtitle track offered by the current stream.
public struct MediaTrack: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Which decoder is playing the current item.
public enum EngineKind: String, Sendable {
    /// AVFoundation, using the hardware decoder.
    case hardware
    /// VLCKit software decoder, for MKV, HEVC-in-MKV, DTS, AVI, etc.
    case software
}
