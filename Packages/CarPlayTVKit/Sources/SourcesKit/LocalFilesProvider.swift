import Foundation

/// Videos imported into the app's own storage. They play offline.
public struct LocalFilesProvider: MediaProvider {
    public static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "ts", "m2ts", "webm", "wmv", "flv", "3gp"]

    public let directory: URL
    public let sourceID: UUID?

    public init(directory: URL, sourceID: UUID? = nil) {
        self.directory = directory
        self.sourceID = sourceID
    }

    public func loadGroups() async throws -> [ChannelGroup] {
        let channels = try listVideos()
        guard !channels.isEmpty else { return [] }
        return [ChannelGroup(id: (sourceID?.uuidString ?? "local") + "/videos", name: "On this iPhone", channels: channels)]
    }

    public func listVideos() throws -> [Channel] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        let videos = files.filter { Self.videoExtensions.contains($0.pathExtension.lowercased()) }
        let dated = videos.map { url -> (URL, Date) in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url, date)
        }
        return dated.sorted { $0.1 > $1.1 }.map { url, _ in
            Channel(
                id: "local:" + url.lastPathComponent,
                name: url.deletingPathExtension().lastPathComponent,
                group: "On this iPhone",
                streamURLs: [url],
                kind: .video,
                sourceID: sourceID
            )
        }
    }

    /// Copies a picked file into `directory`, avoiding name clashes. Returns the new URL.
    @discardableResult
    public static func importFile(at source: URL, into directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        var counter = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }
}
