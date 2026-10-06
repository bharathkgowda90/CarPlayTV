import PlaybackKit
import UIKit
import VLCKitSPM

/// Software decoder (VLCKit) for containers and codecs AVFoundation can't play:
/// MKV, AVI, WMV, FLV, DTS audio, raw MPEG-TS and so on.
@MainActor
final class VLCEngine: PlaybackEngine {
    let kind: EngineKind = .software
    var onEvent: ((EngineEvent) -> Void)?

    private let mediaPlayer = VLCMediaPlayer()
    private var poller: Timer?
    private var lastState: VLCMediaPlayerState = .stopped
    private var lastPlaying = false
    private var didReportReady = false
    private var lastTrackSignature = ""
    private weak var drawingHost: VideoHostView?

    init() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    var isPlaying: Bool { mediaPlayer.isPlaying }

    var currentTime: Double {
        max(0, Double(mediaPlayer.time.intValue) / 1000)
    }

    var duration: Double? {
        guard let length = mediaPlayer.media?.length.intValue, length > 0 else { return nil }
        return Double(length) / 1000
    }

    var audioTracks: [MediaTrack] {
        Self.tracks(names: mediaPlayer.audioTrackNames, indexes: mediaPlayer.audioTrackIndexes)
    }

    var subtitleTracks: [MediaTrack] {
        Self.tracks(names: mediaPlayer.videoSubTitlesNames, indexes: mediaPlayer.videoSubTitlesIndexes)
    }

    var selectedAudioTrackID: String? {
        let index = mediaPlayer.currentAudioTrackIndex
        return index < 0 ? nil : String(index)
    }

    var selectedSubtitleTrackID: String? {
        let index = mediaPlayer.currentVideoSubTitleIndex
        return index < 0 ? nil : String(index)
    }

    func load(url: URL, startAt: Double?) {
        let media = VLCMedia(url: url)
        if let startAt, startAt > 0 { media.addOption(":start-time=\(Int(startAt))") }
        media.addOption(":network-caching=1500")
        lastState = .stopped
        lastPlaying = false
        didReportReady = false
        lastTrackSignature = ""
        mediaPlayer.media = media
        mediaPlayer.play()
    }

    func play() { mediaPlayer.play() }
    func pause() { mediaPlayer.pause() }

    func seek(to seconds: Double) {
        mediaPlayer.time = VLCTime(int: Int32(max(0, seconds) * 1000))
    }

    func stop() {
        mediaPlayer.stop()
        mediaPlayer.media = nil
    }

    func setVolume(_ volume: Float) {
        // `as VLCAudio?` works whether VLCKit declares `audio` optional or not.
        guard let audio = mediaPlayer.audio as VLCAudio? else { return }
        audio.volume = Int32(min(1, max(0, volume)) * 100)
    }

    func selectAudioTrack(id: String) {
        guard let index = Int32(id) else { return }
        mediaPlayer.currentAudioTrackIndex = index
        onEvent?(.tracksChanged)
    }

    func selectSubtitleTrack(id: String?) {
        mediaPlayer.currentVideoSubTitleIndex = id.flatMap { Int32($0) } ?? -1
        onEvent?(.tracksChanged)
    }

    /// VLC draws into one view. Moving playback to another view (phone → car) restarts
    /// the stream at the current position, which VLCKit needs to switch surfaces.
    func attach(to host: VideoHostView) {
        guard drawingHost !== host else { return }
        drawingHost = host
        let isActive = mediaPlayer.media != nil && (mediaPlayer.isPlaying || mediaPlayer.state == .paused)
        if isActive, let url = mediaPlayer.media?.url {
            let position = currentTime
            mediaPlayer.stop()
            mediaPlayer.drawable = host.softwareDrawable
            load(url: url, startAt: position > 0 ? position : nil)
        } else {
            mediaPlayer.drawable = host.softwareDrawable
        }
    }

    func detach(from host: VideoHostView) {
        guard drawingHost === host else { return }
        drawingHost = nil
        mediaPlayer.drawable = nil
    }

    // MARK: - Private

    private func poll() {
        let playing = mediaPlayer.isPlaying
        if playing != lastPlaying {
            lastPlaying = playing
            onEvent?(.playingChanged(playing))
        }
        if playing, !didReportReady {
            didReportReady = true
            onEvent?(.ready)
        }
        let state = mediaPlayer.state
        if state != lastState {
            lastState = state
            switch state {
            case .error: onEvent?(.failed("This stream could not be played."))
            case .ended: onEvent?(.ended)
            default: break
            }
        }
        let signature = "\(mediaPlayer.numberOfAudioTracks)/\(mediaPlayer.numberOfSubtitlesTracks)"
        if signature != lastTrackSignature {
            lastTrackSignature = signature
            onEvent?(.tracksChanged)
        }
    }

    private static func tracks(names: [Any]?, indexes: [Any]?) -> [MediaTrack] {
        guard let names, let indexes else { return [] }
        return zip(names, indexes).compactMap { name, index in
            guard let number = index as? NSNumber, number.intValue >= 0 else { return nil }
            return MediaTrack(id: number.stringValue, name: (name as? String) ?? "Track \(number)")
        }
    }
}
