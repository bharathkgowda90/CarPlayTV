#if os(iOS)
import AVFoundation
import UIKit

/// Hardware-decoded playback through AVFoundation. Any number of hosts can show it.
@MainActor
public final class AVPlayerEngine: PlaybackEngine {
    public let kind: EngineKind = .hardware
    public var onEvent: ((EngineEvent) -> Void)?

    public let player = AVPlayer()
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []
    public private(set) var selectedAudioTrackID: String?
    public private(set) var selectedSubtitleTrackID: String?

    private var hosts: [WeakHost] = []
    private var timeControlObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var pendingStart: Double?
    private var audioOptions: [String: AVMediaSelectionOption] = [:]
    private var subtitleOptions: [String: AVMediaSelectionOption] = [:]
    private var audibleGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?

    public init() {
        // Video is drawn by our own layers on the car window, not routed over AirPlay.
        player.allowsExternalPlayback = false
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.onEvent?(.playingChanged(playing)) }
        }
    }

    public var isPlaying: Bool { player.timeControlStatus != .paused }

    public var currentTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    public var duration: Double? {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    public func load(url: URL, startAt: Double?) {
        resetTracks()
        pendingStart = startAt
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription ?? "This stream could not be played."
            Task { @MainActor in self?.itemStatusChanged(item, status: status, message: message) }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.ended) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    public func play() { player.play() }
    public func pause() { player.pause() }

    public func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        resetTracks()
    }

    public func setVolume(_ volume: Float) {
        player.volume = min(1, max(0, volume))
    }

    public func selectAudioTrack(id: String) {
        guard let item = player.currentItem, let option = audioOptions[id],
              let group = audibleGroup else { return }
        item.select(option, in: group)
        selectedAudioTrackID = id
        onEvent?(.tracksChanged)
    }

    public func selectSubtitleTrack(id: String?) {
        guard let item = player.currentItem,
              let group = legibleGroup else { return }
        item.select(id.flatMap { subtitleOptions[$0] }, in: group)
        selectedSubtitleTrackID = id
        onEvent?(.tracksChanged)
    }

    public func attach(to host: VideoHostView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        hosts.append(WeakHost(view: host))
        host.playerLayer.player = player
    }

    public func detach(from host: VideoHostView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        host.playerLayer.player = nil
    }

    // MARK: - Private

    private func itemStatusChanged(_ item: AVPlayerItem, status: AVPlayerItem.Status, message: String) {
        guard player.currentItem === item else { return }
        switch status {
        case .readyToPlay:
            if let start = pendingStart, start > 0 { seek(to: start) }
            pendingStart = nil
            onEvent?(.ready)
            Task { await loadTracks(for: item) }
        case .failed:
            onEvent?(.failed(message))
        default:
            break
        }
    }

    private func loadTracks(for item: AVPlayerItem) async {
        let asset = item.asset
        let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
        let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
        guard player.currentItem === item else { return }

        audibleGroup = audible
        legibleGroup = legible
        audioOptions = [:]
        subtitleOptions = [:]
        audioTracks = (audible?.options ?? []).enumerated().map { index, option in
            let id = "a\(index)"
            audioOptions[id] = option
            return MediaTrack(id: id, name: option.displayName)
        }
        subtitleTracks = (legible?.options ?? []).enumerated().map { index, option in
            let id = "s\(index)"
            subtitleOptions[id] = option
            return MediaTrack(id: id, name: option.displayName)
        }
        if let audible, let selected = item.currentMediaSelection.selectedMediaOption(in: audible) {
            selectedAudioTrackID = audioOptions.first { $0.value == selected }?.key
        }
        if let legible, let selected = item.currentMediaSelection.selectedMediaOption(in: legible) {
            selectedSubtitleTrackID = subtitleOptions.first { $0.value == selected }?.key
        }
        onEvent?(.tracksChanged)
    }

    private func resetTracks() {
        audioTracks = []
        subtitleTracks = []
        audioOptions = [:]
        subtitleOptions = [:]
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        audibleGroup = nil
        legibleGroup = nil
    }
}

struct WeakHost {
    weak var view: VideoHostView?
}
#endif
