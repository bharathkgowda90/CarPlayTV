import Foundation

/// A place the user gets video from. Secrets (passwords) are kept in the Keychain,
/// never in this struct.
public struct Source: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case m3u(url: URL)
        case xtream(server: URL, username: String)
        case jellyfin(server: URL, username: String)
        case emby(server: URL, username: String)
        case localFiles
    }

    public let id: UUID
    public var name: String
    public var kind: Kind

    public init(id: UUID = UUID(), name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public var needsPassword: Bool {
        switch kind {
        case .xtream, .jellyfin, .emby: return true
        case .m3u, .localFiles: return false
        }
    }

    public var kindLabel: String {
        switch kind {
        case .m3u: return "M3U playlist"
        case .xtream: return "Xtream Codes"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        case .localFiles: return "On this iPhone"
        }
    }

    public var passwordAccount: String { "source-\(id.uuidString)-password" }
}
