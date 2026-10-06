import MirrorKit
import Observation
import PlaybackKit
import UIKit

/// Root view controller of the CarPlay window: full-screen video, plus a message when
/// there is nothing to show or video is paused because the car is moving.
@MainActor
final class VideoCanvasViewController: UIViewController {
    private let model: AppModel
    private let videoHost = VideoHostView(priority: 10)
    private let mirrorView = MirrorDisplayView()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        videoHost.frame = view.bounds
        videoHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(videoHost)
        model.player.register(videoHost)

        mirrorView.frame = view.bounds
        mirrorView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mirrorView.isHidden = true
        view.addSubview(mirrorView)
        model.mirror.register(mirrorView)

        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            messageLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            spinner.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
        ])

        observeState()
    }

    func tearDown() {
        model.player.unregister(videoHost)
        model.mirror.unregister(mirrorView)
    }

    private func observeState() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeState() }
        }
    }

    private func render() {
        let player = model.player
        let videoAllowed = model.driveMonitor.isVideoAllowed
        let mirroring = model.isMirroring
        // Hiding the surface stops video on the car screen; the player keeps playing audio.
        videoHost.isHidden = !videoAllowed || mirroring
        mirrorView.isHidden = !videoAllowed || !mirroring

        let message: String?
        if !videoAllowed {
            message = "Video paused while driving.\nAudio keeps playing."
        } else if mirroring {
            message = nil
        } else if let error = player.errorMessage {
            message = error
        } else if player.currentChannel == nil {
            message = "Tap Browse, or pick something on your iPhone."
        } else {
            message = nil
        }
        messageLabel.text = message
        messageLabel.isHidden = message == nil

        if player.isLoading && videoAllowed { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}
