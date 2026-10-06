import Foundation
import SourcesKit

public struct StreamHealth: Sendable, Hashable {
    public let isReachable: Bool
    /// Time to the server's first response, in milliseconds.
    public let latencyMilliseconds: Int?
    public let checkedAt: Date
}

/// Probes live streams in the background so dead channels can be hidden and slow ones
/// flagged. Only the stream URLs already in the user's sources are contacted.
public actor HealthChecker {
    private let session: URLSession
    private let maxConcurrent: Int
    private var results: [String: StreamHealth] = [:]

    public init(timeout: TimeInterval = 8, maxConcurrent: Int = 6) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        self.maxConcurrent = maxConcurrent
    }

    public func health(for channelID: String) -> StreamHealth? { results[channelID] }

    public func allResults() -> [String: StreamHealth] { results }

    /// Checks every live channel, reporting each result as it arrives.
    public func check(_ channels: [Channel], onResult: @escaping @Sendable (String, StreamHealth) async -> Void) async {
        let targets = channels.filter { $0.isLive && $0.isPlayable }
        let session = self.session
        await withTaskGroup(of: (String, StreamHealth).self) { group in
            var nextIndex = 0
            while nextIndex < min(maxConcurrent, targets.count) {
                let channel = targets[nextIndex]
                group.addTask { (channel.id, await Self.probe(channel: channel, session: session)) }
                nextIndex += 1
            }
            while let (id, health) = await group.next() {
                results[id] = health
                await onResult(id, health)
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if nextIndex < targets.count {
                    let channel = targets[nextIndex]
                    group.addTask { (channel.id, await Self.probe(channel: channel, session: session)) }
                    nextIndex += 1
                }
            }
        }
    }

    /// A channel is healthy if any of its lines answers with a 2xx/3xx status.
    static func probe(channel: Channel, session: URLSession) async -> StreamHealth {
        for url in channel.streamURLs {
            if let latency = await probe(url: url, session: session) {
                return StreamHealth(isReachable: true, latencyMilliseconds: latency, checkedAt: Date())
            }
        }
        return StreamHealth(isReachable: false, latencyMilliseconds: nil, checkedAt: Date())
    }

    private static func probe(url: URL, session: URLSession) async -> Int? {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let start = Date()
        do {
            // `bytes(for:)` returns once headers arrive, so endless live streams don't block.
            let (bytes, response) = try await session.bytes(for: request)
            bytes.task.cancel()
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return nil }
            return Int(Date().timeIntervalSince(start) * 1000)
        } catch {
            return nil
        }
    }
}
