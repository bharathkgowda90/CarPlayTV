import Foundation
import LibraryKit
import MirrorKit
import Observation
import PlaybackKit
import ReceiverKit
import SafetyKit
import SourcesKit

/// What one source contributed to the library.
struct SourceContent: Identifiable {
    var id: UUID { source.id }
    let source: Source
    var groups: [ChannelGroup] = []
    var isLoading = false
    var error: String?
}

/// App-wide state shared by the iPhone scene and the CarPlay scene.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings = AppSettings()
    let library: LibraryStore
    let player = PlayerController()
    let driveMonitor = DriveStateMonitor()

    private(set) var contents: [SourceContent] = []
    private(set) var localVideos: [Channel] = []
    private(set) var health: [String: StreamHealth] = [:]
    var isCarConnected = false

    /// Running UPnP/DLNA receiver, if Receive is on.
    var receiver: MediaRendererService?
    var receiverError: String?
    let activity = CastActivityController()

    /// Screen mirroring from the broadcast extension.
    let mirror = MirrorReceiver()
    var isMirroring = false
    var mirrorError: String?

    /// Folder for imported videos. It's in Documents so it also shows in the Files app.
    let localVideosDirectory: URL

    @ObservationIgnored private let healthChecker = HealthChecker()
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var pendingHealth: [String: StreamHealth] = [:]
    @ObservationIgnored private var providers: [UUID: any MediaProvider] = [:]

    init() {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        library = LibraryStore(directory: support.appendingPathComponent("Library", isDirectory: true))
        localVideosDirectory = documents.appendingPathComponent("Videos", isDirectory: true)
        try? fileManager.createDirectory(at: localVideosDirectory, withIntermediateDirectories: true)

        player.softwareEngineFactory = { VLCEngine() }
        player.preferSoftwareDecoder = settings.preferSoftwareDecoder
        player.resumePositionProvider = { [weak self] channel in self?.library.resumePosition(for: channel) }
        player.onProgress = { [weak self] channel, position, duration in
            self?.library.recordProgress(for: channel, position: position, duration: duration)
        }
        startMirrorListener()
    }

    // MARK: - Loading

    func reloadAll() async {
        refreshLocalVideos()
        contents = library.sources.map { SourceContent(source: $0, isLoading: true) }
        await withTaskGroup(of: Void.self) { group in
            for source in library.sources {
                group.addTask { await self.reload(source) }
            }
        }
        startHealthCheck()
    }

    func reload(_ source: Source) async {
        setContent(for: source) { $0.isLoading = true; $0.error = nil }
        do {
            let provider = try makeProvider(for: source)
            let groups = try await provider.loadGroups()
            setContent(for: source) { $0.groups = groups; $0.isLoading = false }
        } catch {
            setContent(for: source) { $0.isLoading = false; $0.error = error.localizedDescription }
        }
    }

    func children(of item: Channel) async throws -> [ChannelGroup] {
        guard let sourceID = item.sourceID, let source = library.sources.first(where: { $0.id == sourceID }) else { return [] }
        return try await makeProvider(for: source).children(of: item)
    }

    func refreshLocalVideos() {
        localVideos = (try? LocalFilesProvider(directory: localVideosDirectory).listVideos()) ?? []
    }

    private func makeProvider(for source: Source) throws -> any MediaProvider {
        if let cached = providers[source.id] { return cached }
        let provider = try MediaProviderFactory.provider(
            for: source,
            password: library.password(for: source),
            localDirectory: localVideosDirectory,
            deviceID: settings.deviceID
        )
        providers[source.id] = provider
        return provider
    }

    private func setContent(for source: Source, _ change: (inout SourceContent) -> Void) {
        if let index = contents.firstIndex(where: { $0.source.id == source.id }) {
            change(&contents[index])
        } else {
            var content = SourceContent(source: source)
            change(&content)
            contents.append(content)
        }
    }

    // MARK: - Sources

    func addSource(_ source: Source, password: String?) async {
        library.addSource(source, password: password)
        await reload(source)
        startHealthCheck()
    }

    func updateSource(_ source: Source, password: String?) async {
        library.updateSource(source, password: password)
        providers[source.id] = nil
        await reload(source)
    }

    func removeSource(_ source: Source) {
        library.removeSource(source)
        providers[source.id] = nil
        contents.removeAll { $0.source.id == source.id }
    }

    func importLocalVideo(from url: URL) throws {
        try LocalFilesProvider.importFile(at: url, into: localVideosDirectory)
        refreshLocalVideos()
    }

    func deleteLocalVideo(_ channel: Channel) {
        guard let url = channel.streamURLs.first, url.isFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        refreshLocalVideos()
    }

    // MARK: - Browsing

    /// Rows for the home screen, with dead channels hidden when that setting is on.
    func visibleGroups(of content: SourceContent) -> [ChannelGroup] {
        content.groups.compactMap { group in
            let channels = visibleChannels(group.channels)
            return channels.isEmpty ? nil : ChannelGroup(id: group.id, name: group.name, channels: channels)
        }
    }

    func visibleChannels(_ channels: [Channel]) -> [Channel] {
        guard settings.hideDeadChannels else { return channels }
        return channels.filter { health[$0.id]?.isReachable != false }
    }

    var allChannels: [Channel] {
        contents.flatMap { $0.groups.flatMap(\.channels) } + localVideos
    }

    func search(_ query: String) -> [Channel] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return Array(allChannels.lazy.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }.prefix(300))
    }

    /// Plays an item with its group as the next/previous queue.
    func play(_ channel: Channel, in list: [Channel]? = nil) {
        player.preferSoftwareDecoder = settings.preferSoftwareDecoder
        player.play(channel, in: list.map(visibleChannels))
    }

    // MARK: - Health checks

    func startHealthCheck() {
        healthTask?.cancel()
        guard settings.healthCheckEnabled else { return }
        let live = Array(contents.flatMap { $0.groups.flatMap(\.channels) }.filter(\.isLive).prefix(3000))
        guard !live.isEmpty else { return }
        healthTask = Task { [weak self, healthChecker] in
            await healthChecker.check(live) { id, result in
                await self?.receiveHealth(id: id, result: result)
            }
            await self?.flushHealth()
        }
    }

    func recheckHealth() {
        health = [:]
        startHealthCheck()
    }

    private func receiveHealth(id: String, result: StreamHealth) {
        pendingHealth[id] = result
        // Publish in batches so long playlists don't redraw the UI thousands of times.
        if pendingHealth.count >= 40 { flushHealth() }
    }

    private func flushHealth() {
        guard !pendingHealth.isEmpty else { return }
        health.merge(pendingHealth) { _, new in new }
        pendingHealth = [:]
    }
}
