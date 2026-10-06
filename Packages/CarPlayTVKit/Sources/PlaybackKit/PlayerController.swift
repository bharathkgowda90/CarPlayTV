import AVFoundation
import Observation
import SourcesKit

/// The single player shared by the phone UI and the car display. Any number of
/// `AVPlayerLayer`s can show `player`, so each screen attaches its own layer.
@MainActor
@Observable
public final class PlayerController {
    public let player = AVPlayer()

    public private(set) var queue: [Channel] = []
    public private(set) var currentIndex: Int?
    public private(set) var currentLineIndex = 0
    public private(set) var isPlaying = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?

    public init() {
        // Video is drawn by our own layers on the car window, not routed over AirPlay.
        player.allowsExternalPlayback = false
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    public var currentChannel: Channel? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    /// Plays `channel`. Pass `queue` to make next/previous move through that list.
    public func play(_ channel: Channel, in queue: [Channel]? = nil) {
        if let queue { self.queue = queue }
        if let index = self.queue.firstIndex(of: channel) {
            currentIndex = index
        } else {
            self.queue.append(channel)
            currentIndex = self.queue.count - 1
        }
        currentLineIndex = 0
        startCurrent()
    }

    public func play(url: URL, title: String? = nil) {
        play(Channel(name: title ?? url.lastPathComponent, streamURLs: [url]))
    }

    public func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if isPlaying { player.pause() } else { player.play() }
    }

    public func next() { step(by: 1) }
    public func previous() { step(by: -1) }

    /// Moves to the channel's next stream URL, if it has more than one.
    public func switchLine() {
        guard let channel = currentChannel, channel.streamURLs.count > 1 else { return }
        currentLineIndex = (currentLineIndex + 1) % channel.streamURLs.count
        startCurrent()
    }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatusObservation = nil
        currentIndex = nil
        errorMessage = nil
    }

    #if os(iOS)
    public static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }
    #endif

    // MARK: - Private

    private func step(by delta: Int) {
        guard let currentIndex, !queue.isEmpty else { return }
        self.currentIndex = (currentIndex + delta + queue.count) % queue.count
        currentLineIndex = 0
        startCurrent()
    }

    private func startCurrent() {
        guard let channel = currentChannel else { return }
        errorMessage = nil
        let item = AVPlayerItem(url: channel.streamURLs[currentLineIndex])
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "This stream could not be played."
            Task { @MainActor in self?.handleFailure(of: item, message: message) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func handleFailure(of item: AVPlayerItem, message: String) {
        guard player.currentItem === item, let channel = currentChannel else { return }
        if currentLineIndex + 1 < channel.streamURLs.count {
            currentLineIndex += 1
            startCurrent()
        } else {
            errorMessage = message
        }
    }
}
