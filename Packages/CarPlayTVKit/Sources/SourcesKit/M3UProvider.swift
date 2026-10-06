import Foundation

public struct M3UProvider: MediaProvider {
    public let url: URL
    public let sourceID: UUID?
    let session: URLSession

    public init(url: URL, sourceID: UUID? = nil, session: URLSession = .shared) {
        self.url = url
        self.sourceID = sourceID
        self.session = session
    }

    public func loadGroups() async throws -> [ChannelGroup] {
        var channels = try await PlaylistLoader.load(from: url, session: session)
        for index in channels.indices { channels[index].sourceID = sourceID }
        return ChannelGroup.grouping(channels, idPrefix: (sourceID?.uuidString ?? "") + "/")
    }
}
