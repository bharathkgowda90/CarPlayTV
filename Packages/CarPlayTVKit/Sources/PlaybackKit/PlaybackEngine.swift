#if os(iOS)
import UIKit

public enum EngineEvent: Sendable {
    case playingChanged(Bool)
    case ready
    case failed(String)
    case ended
    case tracksChanged
}

/// A decoder backend. `AVPlayerEngine` is built in; the app registers a VLCKit engine
/// for formats AVFoundation can't play.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var kind: EngineKind { get }
    var onEvent: ((EngineEvent) -> Void)? { get set }

    var isPlaying: Bool { get }
    /// Seconds since the start of the item.
    var currentTime: Double { get }
    /// Seconds, or nil for live streams and unknown lengths.
    var duration: Double? { get }

    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    var selectedAudioTrackID: String? { get }
    var selectedSubtitleTrackID: String? { get }

    func load(url: URL, startAt: Double?)
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()

    /// 0...1
    func setVolume(_ volume: Float)

    func selectAudioTrack(id: String)
    /// nil turns embedded subtitles off.
    func selectSubtitleTrack(id: String?)

    /// Shows video in `host`. Engines that can only draw in one place use the most
    /// recently attached host.
    func attach(to host: VideoHostView)
    func detach(from host: VideoHostView)
}
#endif
