#if os(iOS)
import AVFoundation
import Observation
import SourcesKit
import UIKit

/// The single player shared by the iPhone UI and the car display.
///
/// Playback order for an item: hardware decoder on line 1 → software decoder on line 1
/// → hardware on line 2 → … until something plays. Containers that AVFoundation never
/// handles (MKV, AVI, …) go straight to the software decoder.
@MainActor
@Observable
public final class PlayerController {
    public private(set) var queue: [Channel] = []
    public private(set) var currentIndex: Int?
    public private(set) var currentLineIndex = 0
    public private(set) var isPlaying = false
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var currentTime: Double = 0
    public private(set) var duration: Double?
    public private(set) var engineKind: EngineKind = .hardware

    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []
    public private(set) var selectedAudioTrackID: String?
    public private(set) var selectedSubtitleTrackID: String?
    /// File name of loaded external subtitles, if any.
    public private(set) var externalSubtitleName: String?
    /// Delay applied to external subtitles, in seconds (positive shows them later).
    public var subtitleOffset: Double = 0

    /// Always use the software decoder when one is available.
    public var preferSoftwareDecoder = false
    public private(set) var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// Supplies the VLCKit engine (lives in the app target).
    @ObservationIgnored public var softwareEngineFactory: (@MainActor () -> PlaybackEngine)?
    /// Where to resume an item, from the library.
    @ObservationIgnored public var resumePositionProvider: ((Channel) -> Double?)?
    /// Called every few seconds and on stop with (item, position, duration).
    @ObservationIgnored public var onProgress: ((Channel, Double, Double) -> Void)?

    @ObservationIgnored private let hardwareEngine = AVPlayerEngine()
    @ObservationIgnored private var softwareEngine: PlaybackEngine?
    @ObservationIgnored private var usingSoftware = false
    @ObservationIgnored private var hosts: [WeakHost] = []
    @ObservationIgnored private var triedSoftwareForLine = false
    @ObservationIgnored private var lineStartPosition: Double?
    @ObservationIgnored private var subtitleCues: [SubtitleCue] = []
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var lastProgressReport = Date.distantPast
    @ObservationIgnored private var lastNowPlayingUpdate = Date.distantPast
    @ObservationIgnored private let nowPlaying = NowPlayingCoordinator()

    private var engine: PlaybackEngine {
        if usingSoftware, let softwareEngine { return softwareEngine }
        return hardwareEngine
    }

    public init() {
        wire(hardwareEngine)
        startTicker()
        nowPlaying.bind(to: self)
    }

    public static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    // MARK: - Queue

    public var currentChannel: Channel? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    public var isLive: Bool { currentChannel?.isLive ?? false }
    public var canSeek: Bool { !isLive && duration != nil }

    /// Plays `channel`. Pass `queue` so next/previous move through that list.
    public func play(_ channel: Channel, in queue: [Channel]? = nil) {
        guard channel.isPlayable else { return }
        reportProgress(force: true)
        if let queue { self.queue = queue.filter(\.isPlayable) }
        if let index = self.queue.firstIndex(where: { $0.id == channel.id }) {
            currentIndex = index
        } else {
            self.queue.append(channel)
            currentIndex = self.queue.count - 1
        }
        currentLineIndex = 0
        clearExternalSubtitles()
        startLine(startAt: resumePositionProvider?(channel))
    }

    public func play(url: URL, title: String? = nil) {
        let kind: Channel.Kind = url.isFileURL ? .video : (url.pathExtension.lowercased() == "m3u8" ? .live : .movie)
        play(Channel(name: title ?? url.lastPathComponent, streamURLs: [url], kind: kind))
    }

    public func resume() { engine.play() }
    public func pause() {
        engine.pause()
        reportProgress(force: true)
    }

    public func togglePlayPause() {
        guard currentChannel != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    public func next() { step(by: 1) }
    public func previous() { step(by: -1) }

    /// Moves to the channel's next stream URL, if it has more than one.
    public func switchLine() {
        guard let channel = currentChannel, channel.streamURLs.count > 1 else { return }
        currentLineIndex = (currentLineIndex + 1) % channel.streamURLs.count
        startLine(startAt: canSeek ? currentTime : nil)
    }

    public func seek(to seconds: Double) {
        guard canSeek else { return }
        let target = min(max(0, seconds), duration ?? seconds)
        engine.seek(to: target)
        currentTime = target
        updateNowPlaying(force: true)
    }

    public func skip(by seconds: Double) { seek(to: currentTime + seconds) }

    public func stop() {
        reportProgress(force: true)
        engine.stop()
        currentIndex = nil
        isPlaying = false
        isLoading = false
        errorMessage = nil
        currentTime = 0
        duration = nil
        clearExternalSubtitles()
        syncTracks()
        nowPlaying.clear()
    }

    // MARK: - Tracks & subtitles

    public func selectAudioTrack(id: String) { engine.selectAudioTrack(id: id) }

    public func selectSubtitleTrack(id: String?) {
        if id != nil { clearExternalSubtitles() }
        engine.selectSubtitleTrack(id: id)
    }

    /// Loads an .srt / .vtt file (local or remote) and shows it with our own overlay.
    public func loadExternalSubtitles(from url: URL) async throws {
        let data: Data
        if url.isFileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            data = try Data(contentsOf: url)
        } else {
            data = try await URLSession.shared.data(from: url).0
        }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let cues = SubtitleParser.parse(text)
        guard !cues.isEmpty else { throw SubtitleError.noCues }
        engine.selectSubtitleTrack(id: nil)
        subtitleCues = cues
        externalSubtitleName = url.lastPathComponent
        subtitleOffset = 0
    }

    public func clearExternalSubtitles() {
        subtitleCues = []
        externalSubtitleName = nil
        for host in liveHosts { host.setSubtitle(nil) }
    }

    public enum SubtitleError: LocalizedError {
        case noCues
        public var errorDescription: String? { "No subtitles were found in that file." }
    }

    // MARK: - Video surfaces

    /// Registers a surface. Hardware video shows on every surface; the software decoder
    /// draws only on the highest-priority one (the car screen when connected).
    public func register(_ host: VideoHostView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        hosts.append(WeakHost(view: host))
        host.videoGravity = videoGravity
        attachHosts()
    }

    public func unregister(_ host: VideoHostView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        hardwareEngine.detach(from: host)
        softwareEngine?.detach(from: host)
        attachHosts()
    }

    /// Fit (letterbox) or fill (crop) the video.
    public func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        videoGravity = gravity
        for host in liveHosts { host.videoGravity = gravity }
    }

    private var liveHosts: [VideoHostView] {
        hosts.removeAll { $0.view == nil }
        return hosts.compactMap(\.view)
    }

    private func attachHosts() {
        let all = liveHosts
        if usingSoftware, let softwareEngine {
            for host in all { hardwareEngine.detach(from: host) }
            if let top = all.max(by: { $0.priority < $1.priority }) { softwareEngine.attach(to: top) }
        } else {
            for host in all {
                softwareEngine?.detach(from: host)
                hardwareEngine.attach(to: host)
            }
        }
    }

    // MARK: - Loading

    private func step(by delta: Int) {
        guard let currentIndex, !queue.isEmpty else { return }
        reportProgress(force: true)
        self.currentIndex = (currentIndex + delta + queue.count) % queue.count
        currentLineIndex = 0
        clearExternalSubtitles()
        startLine(startAt: currentChannel.flatMap { resumePositionProvider?($0) })
    }

    private func startLine(startAt: Double?) {
        guard let channel = currentChannel else { return }
        triedSoftwareForLine = false
        lineStartPosition = startAt
        let url = channel.streamURLs[currentLineIndex]
        let software = softwareEngineFactory != nil && (preferSoftwareDecoder || Self.needsSoftwareDecoder(url))
        triedSoftwareForLine = software
        load(url, software: software, startAt: startAt)
    }

    private func load(_ url: URL, software: Bool, startAt: Double?) {
        errorMessage = nil
        isLoading = true
        currentTime = startAt ?? 0
        duration = nil
        switchEngine(toSoftware: software)
        engine.load(url: url, startAt: startAt)
        syncTracks()
        updateNowPlaying(force: true)
    }

    private func switchEngine(toSoftware: Bool) {
        if toSoftware, softwareEngine == nil, let factory = softwareEngineFactory {
            let created = factory()
            wire(created)
            softwareEngine = created
        }
        let wantSoftware = toSoftware && softwareEngine != nil
        guard wantSoftware != usingSoftware else { return }
        engine.stop()
        usingSoftware = wantSoftware
        engineKind = engine.kind
        attachHosts()
    }

    private func wire(_ engine: PlaybackEngine) {
        engine.onEvent = { [weak self, weak engine] event in
            guard let self, let engine else { return }
            self.handle(event, from: engine)
        }
    }

    private func handle(_ event: EngineEvent, from source: PlaybackEngine) {
        guard source === engine else { return }
        switch event {
        case .playingChanged(let playing):
            isPlaying = playing
            if playing { isLoading = false }
            updateNowPlaying(force: true)
        case .ready:
            isLoading = false
            duration = engine.duration
            syncTracks()
            updateNowPlaying(force: true)
        case .failed(let message):
            handleFailure(message)
        case .ended:
            reportProgress(force: true)
            isPlaying = false
            updateNowPlaying(force: true)
        case .tracksChanged:
            syncTracks()
        }
    }

    private func handleFailure(_ message: String) {
        guard let channel = currentChannel else { return }
        let url = channel.streamURLs[currentLineIndex]
        if !triedSoftwareForLine, softwareEngineFactory != nil {
            triedSoftwareForLine = true
            load(url, software: true, startAt: lineStartPosition)
            return
        }
        if currentLineIndex + 1 < channel.streamURLs.count {
            currentLineIndex += 1
            startLine(startAt: lineStartPosition)
            return
        }
        isLoading = false
        isPlaying = false
        errorMessage = message
    }

    private func syncTracks() {
        audioTracks = engine.audioTracks
        subtitleTracks = engine.subtitleTracks
        selectedAudioTrackID = engine.selectedAudioTrackID
        selectedSubtitleTrackID = engine.selectedSubtitleTrackID
    }

    static func needsSoftwareDecoder(_ url: URL) -> Bool {
        ["mkv", "avi", "wmv", "flv", "webm", "rmvb", "rm", "ogv", "divx", "vob", "m2ts", "mts"].contains(url.pathExtension.lowercased())
    }

    // MARK: - Ticking

    private func startTicker() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard currentChannel != nil else { return }
        let time = engine.currentTime
        if abs(time - currentTime) >= 0.2 { currentTime = time }
        if duration == nil, let length = engine.duration { duration = length }

        if !subtitleCues.isEmpty {
            let text = SubtitleParser.text(at: time - subtitleOffset, in: subtitleCues)
            for host in liveHosts { host.setSubtitle(text) }
        }
        reportProgress(force: false)
        updateNowPlaying(force: false)
    }

    private func reportProgress(force: Bool) {
        guard let channel = currentChannel, !channel.isLive, let duration, duration > 0 else { return }
        guard force || Date().timeIntervalSince(lastProgressReport) >= 5 else { return }
        lastProgressReport = Date()
        onProgress?(channel, engine.currentTime, duration)
    }

    private func updateNowPlaying(force: Bool) {
        guard force || Date().timeIntervalSince(lastNowPlayingUpdate) >= 5 else { return }
        lastNowPlayingUpdate = Date()
        guard let channel = currentChannel else { return }
        nowPlaying.update(channel: channel, isPlaying: isPlaying, time: currentTime, duration: duration)
    }
}
#endif
