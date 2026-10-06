import Foundation

/// An item from a source: a live channel, a movie, an episode, a local video, or a
/// series (a container whose episodes are loaded on demand). Playable items have one or
/// more stream URLs ("lines"); the player falls back to the next line when one fails.
public struct Channel: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable {
        case live, movie, series, episode, video
    }

    public let id: String
    public let name: String
    public let group: String?
    public let logoURL: URL?
    public let tvgID: String?
    public internal(set) var streamURLs: [URL]
    public let kind: Kind
    public let overview: String?
    public let durationSeconds: Double?
    /// The saved source this item came from.
    public var sourceID: UUID?
    /// Provider-specific identifier used to load children (e.g. a series' episodes).
    public let containerID: String?

    public init(
        id: String? = nil,
        name: String,
        group: String? = nil,
        logoURL: URL? = nil,
        tvgID: String? = nil,
        streamURLs: [URL],
        kind: Kind = .live,
        overview: String? = nil,
        durationSeconds: Double? = nil,
        sourceID: UUID? = nil,
        containerID: String? = nil
    ) {
        self.id = id ?? ((streamURLs.first?.absoluteString ?? containerID ?? "") + "#" + name)
        self.name = name
        self.group = group
        self.logoURL = logoURL
        self.tvgID = tvgID
        self.streamURLs = streamURLs
        self.kind = kind
        self.overview = overview
        self.durationSeconds = durationSeconds
        self.sourceID = sourceID
        self.containerID = containerID
    }

    public var isPlayable: Bool { !streamURLs.isEmpty }
    public var isContainer: Bool { kind == .series }
    public var isLive: Bool { kind == .live }
}

public struct ChannelGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let channels: [Channel]

    public init(id: String? = nil, name: String, channels: [Channel]) {
        self.id = id ?? name
        self.name = name
        self.channels = channels
    }

    /// Groups channels by `group`, keeping the order in which groups first appear.
    public static func grouping(_ channels: [Channel], ungroupedName: String = "Channels", idPrefix: String = "") -> [ChannelGroup] {
        var order: [String] = []
        var buckets: [String: [Channel]] = [:]
        for channel in channels {
            let key = channel.group ?? ungroupedName
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(channel)
        }
        return order.map { ChannelGroup(id: idPrefix + $0, name: $0, channels: buckets[$0] ?? []) }
    }
}
