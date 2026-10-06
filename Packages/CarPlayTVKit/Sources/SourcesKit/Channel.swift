import Foundation

/// A playable entry from a source. A channel can have several stream URLs ("lines");
/// the player falls back to the next line when one fails.
public struct Channel: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let group: String?
    public let logoURL: URL?
    public let tvgID: String?
    public internal(set) var streamURLs: [URL]

    public init(name: String, group: String? = nil, logoURL: URL? = nil, tvgID: String? = nil, streamURLs: [URL]) {
        self.id = (streamURLs.first?.absoluteString ?? "") + "#" + name
        self.name = name
        self.group = group
        self.logoURL = logoURL
        self.tvgID = tvgID
        self.streamURLs = streamURLs
    }
}

public struct ChannelGroup: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let channels: [Channel]

    /// Groups channels by `group`, keeping the order in which groups first appear.
    public static func grouping(_ channels: [Channel], ungroupedName: String = "Channels") -> [ChannelGroup] {
        var order: [String] = []
        var buckets: [String: [Channel]] = [:]
        for channel in channels {
            let key = channel.group ?? ungroupedName
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(channel)
        }
        return order.map { ChannelGroup(name: $0, channels: buckets[$0] ?? []) }
    }
}
